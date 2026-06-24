param(
    [string]$Kubeconfig = (Join-Path $PSScriptRoot "..\kubeconfig"),
    [string]$Kubectl = (Join-Path $HOME "kubectl.exe"),
    [string]$NodeIp,
    [int]$LogstashPort = 30514,
    [int]$EventCount = 240,
    [int]$LocalKibanaPort = 15601
)

$ErrorActionPreference = "Stop"
$namespace = "dockerelk"
$indexPattern = "logstash-dockerelk-infra-*"
$dataViewId = "dockerelk-infra"
$dashboardId = "dockerelk-infra-overview"
$tempDirectory = Join-Path $env:TEMP "dockerelk-kibana-demo"

if (-not $NodeIp) {
    $NodeIp = & $Kubectl --kubeconfig $Kubeconfig get nodes `
        -l node-role.dockerelk.io/control-plane=true `
        -o jsonpath="{.items[0].status.addresses[?(@.type=='InternalIP')].address}"
    if ($LASTEXITCODE -ne 0 -or -not $NodeIp) {
        throw "Adresse du control-plane introuvable."
    }
}

function Invoke-KibanaApi {
    param(
        [string]$Method,
        [string]$Path,
        [string]$BodyFile
    )

    $arguments = @(
        "-ksS",
        "--fail-with-body",
        "-u", "elastic:$script:ElasticPassword",
        "-H", "kbn-xsrf: dockerelk",
        "-H", "Content-Type: application/json",
        "-X", $Method,
        "https://127.0.0.1:$LocalKibanaPort$Path"
    )
    if ($BodyFile) {
        $arguments += @("--data-binary", "@$BodyFile")
    }

    $response = & curl.exe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Appel Kibana impossible : $Method $Path"
    }
    return $response
}

if ($EventCount -lt 24) {
    throw "EventCount doit etre superieur ou egal a 24."
}

$encodedPassword = & $Kubectl --kubeconfig $Kubeconfig `
    -n $namespace get secret dockerelk-es-elastic-user `
    -o jsonpath="{.data.elastic}"
if ($LASTEXITCODE -ne 0 -or -not $encodedPassword) {
    throw "Mot de passe elastic introuvable."
}
$script:ElasticPassword = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($encodedPassword)
)

Write-Host "[1/4] Generation de $EventCount evenements infrastructure"
$hosts = @(
    @{ name = "web-01"; role = "web"; service = "nginx" },
    @{ name = "web-02"; role = "web"; service = "nginx" },
    @{ name = "api-01"; role = "api"; service = "orders-api" },
    @{ name = "db-01"; role = "database"; service = "postgresql" },
    @{ name = "queue-01"; role = "messaging"; service = "rabbitmq" },
    @{ name = "k3s-worker-01"; role = "kubernetes"; service = "kubelet" }
)
$severities = @("info", "info", "info", "warn", "warn", "critical")
$random = [Random]::new(20260624)
$start = (Get-Date).ToUniversalTime().AddHours(-24)

$client = [System.Net.Sockets.TcpClient]::new()
try {
    $client.Connect($NodeIp, $LogstashPort)
    $writer = [System.IO.StreamWriter]::new($client.GetStream())
    $writer.NewLine = "`n"
    $writer.AutoFlush = $true

    for ($i = 0; $i -lt $EventCount; $i++) {
        $hostInfo = $hosts[$i % $hosts.Count]
        $severity = $severities[$random.Next(0, $severities.Count)]
        $cpu = [Math]::Round(20 + $random.NextDouble() * 75, 2)
        if ($severity -eq "critical") {
            $cpu = [Math]::Round(88 + $random.NextDouble() * 10, 2)
        }

        $event = @{
            "@timestamp" = $start.AddSeconds(
                [int](86400 * $i / $EventCount)
            ).ToString("o")
            event = @{
                id       = [guid]::NewGuid().ToString()
                category = "infrastructure"
                severity = $severity
                action   = "resource-sample"
                outcome  = if ($severity -eq "critical") {
                    "failure"
                }
                else {
                    "success"
                }
            }
            host = @{
                name = $hostInfo.name
                role = $hostInfo.role
            }
            service = @{
                name = $hostInfo.service
            }
            metrics = @{
                cpu_percent    = $cpu
                memory_percent = [Math]::Round(
                    30 + $random.NextDouble() * 65,
                    2
                )
                disk_percent = [Math]::Round(
                    25 + $random.NextDouble() * 70,
                    2
                )
                response_time_ms = $random.Next(5, 450)
            }
            message = "$severity sample for $($hostInfo.name)"
        } | ConvertTo-Json -Depth 6 -Compress

        $writer.WriteLine($event)
    }
}
finally {
    if ($writer) {
        $writer.Dispose()
    }
    $client.Dispose()
}

Write-Host "[2/4] Ouverture du tunnel Kibana"
$portForward = Start-Process `
    -FilePath $Kubectl `
    -ArgumentList @(
        "--kubeconfig", $Kubeconfig,
        "-n", $namespace,
        "port-forward",
        "service/dockerelk-kb-http",
        "${LocalKibanaPort}:5601"
    ) `
    -PassThru `
    -WindowStyle Hidden

try {
    New-Item -ItemType Directory -Path $tempDirectory -Force | Out-Null
    Start-Sleep -Seconds 5

    Write-Host "[3/4] Creation du data view et des visualisations"
    $dataViewFile = Join-Path $tempDirectory "data-view.json"
    @{
        data_view = @{
            id            = $dataViewId
            title         = $indexPattern
            name          = "DockerELK Infrastructure"
            timeFieldName = "@timestamp"
        }
        override = $true
    } | ConvertTo-Json -Depth 5 | Set-Content `
        -Path $dataViewFile `
        -Encoding ascii
    Invoke-KibanaApi `
        -Method POST `
        -Path "/api/data_views/data_view" `
        -BodyFile $dataViewFile | Out-Null

    $visualizations = @(
        @{
            id = "dockerelk-events-total"
            title = "Infrastructure events"
            spec = @{
                '$schema' = "https://vega.github.io/schema/vega-lite/v5.json"
                data = @{
                    url = @{
                        '%context%' = $true
                        '%timefield%' = "@timestamp"
                        index = $indexPattern
                        body = @{ size = 0 }
                    }
                    format = @{ property = "hits.total" }
                }
                mark = @{ type = "text"; fontSize = 64; color = "#2b70f7" }
                encoding = @{
                    text = @{ field = "value"; type = "quantitative"; format = "," }
                }
                view = @{ stroke = $null }
            }
        },
        @{
            id = "dockerelk-cpu-over-time"
            title = "Average CPU over time"
            spec = @{
                '$schema' = "https://vega.github.io/schema/vega-lite/v5.json"
                data = @{
                    url = @{
                        '%context%' = $true
                        '%timefield%' = "@timestamp"
                        index = $indexPattern
                        body = @{
                            size = 0
                            aggs = @{
                                timeline = @{
                                    date_histogram = @{
                                        field = "@timestamp"
                                        fixed_interval = "30m"
                                        min_doc_count = 0
                                    }
                                    aggs = @{
                                        cpu = @{ avg = @{ field = "metrics.cpu_percent" } }
                                    }
                                }
                            }
                        }
                    }
                    format = @{ property = "aggregations.timeline.buckets" }
                }
                mark = @{ type = "line"; point = $true; color = "#00bfb3" }
                encoding = @{
                    x = @{
                        field = "key_as_string"
                        type = "temporal"
                        title = "Time"
                    }
                    y = @{
                        field = "cpu.value"
                        type = "quantitative"
                        title = "CPU %"
                        scale = @{ domain = @(0, 100) }
                    }
                }
            }
        },
        @{
            id = "dockerelk-severity"
            title = "Events by severity"
            spec = @{
                '$schema' = "https://vega.github.io/schema/vega-lite/v5.json"
                data = @{
                    url = @{
                        '%context%' = $true
                        '%timefield%' = "@timestamp"
                        index = $indexPattern
                        body = @{
                            size = 0
                            aggs = @{
                                severity = @{
                                    terms = @{
                                        field = "event.severity.keyword"
                                        size = 10
                                    }
                                }
                            }
                        }
                    }
                    format = @{ property = "aggregations.severity.buckets" }
                }
                mark = "bar"
                encoding = @{
                    x = @{
                        field = "key"
                        type = "nominal"
                        title = "Severity"
                        sort = @("critical", "warn", "info")
                    }
                    y = @{
                        field = "doc_count"
                        type = "quantitative"
                        title = "Events"
                    }
                    color = @{
                        field = "key"
                        type = "nominal"
                        scale = @{
                            domain = @("critical", "warn", "info")
                            range = @("#bd271e", "#f5a700", "#2b70f7")
                        }
                        legend = $null
                    }
                }
            }
        }
    )

    $savedObjects = @()
    foreach ($visualization in $visualizations) {
        $visState = @{
            title = $visualization.title
            type = "vega"
            params = @{
                spec = ($visualization.spec | ConvertTo-Json -Depth 20)
            }
            aggs = @()
        } | ConvertTo-Json -Depth 20 -Compress

        $savedObjects += @{
            type = "visualization"
            id = $visualization.id
            attributes = @{
                title = $visualization.title
                description = "Managed by DockerELK_v2 demo automation"
                visState = $visState
                uiStateJSON = "{}"
                kibanaSavedObjectMeta = @{
                    searchSourceJSON = '{"query":{"query":"","language":"kuery"},"filter":[]}'
                }
            }
            references = @()
        }
    }

    Write-Host "[4/4] Creation et validation du dashboard"
    $panels = @(
        @{
            type = "visualization"
            panelIndex = "1"
            panelRefName = "panel_0"
            gridData = @{ x = 0; y = 0; w = 12; h = 10; i = "1" }
            embeddableConfig = @{}
        },
        @{
            type = "visualization"
            panelIndex = "2"
            panelRefName = "panel_1"
            gridData = @{ x = 12; y = 0; w = 36; h = 10; i = "2" }
            embeddableConfig = @{}
        },
        @{
            type = "visualization"
            panelIndex = "3"
            panelRefName = "panel_2"
            gridData = @{ x = 0; y = 10; w = 48; h = 14; i = "3" }
            embeddableConfig = @{}
        }
    )
    $savedObjects += @{
        type = "dashboard"
        id = $dashboardId
        attributes = @{
            title = "DockerELK Infrastructure Overview"
            description = "Infrastructure events generated by the DockerELK_v2 K3s demo."
            panelsJSON = ($panels | ConvertTo-Json -Depth 10 -Compress)
            optionsJSON = '{"useMargins":true,"syncColors":true,"syncCursor":true,"syncTooltips":true}'
            version = 1
            timeRestore = $true
            timeFrom = "now-24h"
            timeTo = "now"
            refreshInterval = @{
                pause = $true
                value = 60000
            }
            kibanaSavedObjectMeta = @{
                searchSourceJSON = '{"query":{"query":"","language":"kuery"},"filter":[]}'
            }
        }
        references = @(
            @{
                name = "panel_0"
                type = "visualization"
                id = "dockerelk-events-total"
            },
            @{
                name = "panel_1"
                type = "visualization"
                id = "dockerelk-cpu-over-time"
            },
            @{
                name = "panel_2"
                type = "visualization"
                id = "dockerelk-severity"
            }
        )
    }

    $ndjsonFile = Join-Path $tempDirectory "dockerelk-dashboard.ndjson"
    $savedObjects |
        ForEach-Object { $_ | ConvertTo-Json -Depth 20 -Compress } |
        Set-Content -Path $ndjsonFile -Encoding ascii

    $importResponse = & curl.exe `
        -ksS `
        --fail-with-body `
        -u "elastic:$script:ElasticPassword" `
        -H "kbn-xsrf: dockerelk" `
        -X POST `
        "https://127.0.0.1:$LocalKibanaPort/api/saved_objects/_import?overwrite=true" `
        -F "file=@$ndjsonFile"
    if ($LASTEXITCODE -ne 0) {
        throw "Import du dashboard Kibana impossible."
    }
    $importResult = $importResponse | ConvertFrom-Json
    if (-not $importResult.success) {
        throw "Import Kibana incomplet : $importResponse"
    }

    Start-Sleep -Seconds 10
    $dashboard = Invoke-KibanaApi `
        -Method GET `
        -Path "/api/saved_objects/_find?type=dashboard&search_fields=title&search=DockerELK%20Infrastructure%20Overview"
    $dashboardObject = $dashboard | ConvertFrom-Json
    if ([int]$dashboardObject.total -ne 1) {
        throw "Le dashboard Kibana n'a pas ete valide."
    }
    $visualizationResponse = Invoke-KibanaApi `
        -Method GET `
        -Path "/api/saved_objects/_find?type=visualization&per_page=20&search_fields=description&search=Managed%20by%20DockerELK_v2"
    $visualizationObjects = $visualizationResponse | ConvertFrom-Json
    if ([int]$visualizationObjects.total -ne 3) {
        throw "Nombre de visualisations inattendu : $($visualizationObjects.total)."
    }

    Write-Host "Dashboard cree : DockerELK Infrastructure Overview"
    Write-Host "Visualisations validees : 3"
    Write-Host "URL via port-forward : https://localhost:5601/app/dashboards#/view/$dashboardId"
}
finally {
    if ($portForward -and -not $portForward.HasExited) {
        Stop-Process -Id $portForward.Id -Force
    }
    Remove-Item -Path $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
    $script:ElasticPassword = $null
}
