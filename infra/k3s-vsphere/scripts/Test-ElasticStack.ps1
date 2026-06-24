param(
    [string]$Kubeconfig = (Join-Path $PSScriptRoot "..\kubeconfig"),
    [string]$Kubectl = (Join-Path $HOME "kubectl.exe"),
    [string]$Namespace = "dockerelk",
    [string]$NodeIp,
    [int]$LogstashPort = 30514,
    [int]$LocalElasticsearchPort = 19200
)

$ErrorActionPreference = "Stop"

if (-not $NodeIp) {
    $NodeIp = & $Kubectl --kubeconfig $Kubeconfig get nodes `
        -l node-role.dockerelk.io/control-plane=true `
        -o jsonpath="{.items[0].status.addresses[?(@.type=='InternalIP')].address}"
    if ($LASTEXITCODE -ne 0 -or -not $NodeIp) {
        throw "Adresse du control-plane introuvable."
    }
}
$eventId = [guid]::NewGuid().ToString()
$timestamp = (Get-Date).ToUniversalTime().ToString("o")
$event = @{
    "@timestamp" = $timestamp
    event = @{
        id       = $eventId
        category = "infrastructure"
        action   = "k3s-deployment-smoke-test"
        outcome  = "success"
    }
    host = @{
        name = "deployment-runner"
    }
    message = "DockerELK_v2 K3s integration test"
} | ConvertTo-Json -Depth 5 -Compress

$deadline = (Get-Date).AddMinutes(3)
do {
    $probe = [System.Net.Sockets.TcpClient]::new()
    try {
        $connect = $probe.BeginConnect($NodeIp, $LogstashPort, $null, $null)
        $portReady = $connect.AsyncWaitHandle.WaitOne(2000) -and $probe.Connected
        if ($portReady) {
            $probe.EndConnect($connect)
            break
        }
    }
    finally {
        $probe.Dispose()
    }
    Start-Sleep -Seconds 5
} while ((Get-Date) -lt $deadline)

if (-not $portReady) {
    throw "Logstash n'ecoute pas sur ${NodeIp}:${LogstashPort}."
}

Write-Host "Envoi de l'evenement $eventId vers Logstash"
$client = [System.Net.Sockets.TcpClient]::new()
try {
    $client.Connect($NodeIp, $LogstashPort)
    $writer = [System.IO.StreamWriter]::new($client.GetStream())
    $writer.NewLine = "`n"
    $writer.AutoFlush = $true
    $writer.WriteLine($event)
}
finally {
    if ($writer) {
        $writer.Dispose()
    }
    $client.Dispose()
}

$encodedPassword = & $Kubectl --kubeconfig $Kubeconfig `
    -n $Namespace get secret dockerelk-es-elastic-user `
    -o jsonpath="{.data.elastic}"
if ($LASTEXITCODE -ne 0 -or -not $encodedPassword) {
    throw "Mot de passe elastic introuvable."
}
$password = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($encodedPassword)
)

$portForward = Start-Process `
    -FilePath $Kubectl `
    -ArgumentList @(
        "--kubeconfig", $Kubeconfig,
        "-n", $Namespace,
        "port-forward",
        "service/dockerelk-es-http",
        "${LocalElasticsearchPort}:9200"
    ) `
    -PassThru `
    -WindowStyle Hidden

try {
    $deadline = (Get-Date).AddMinutes(3)
    do {
        Start-Sleep -Seconds 5
        $query = [Uri]::EscapeDataString("event.id:$eventId")

        $response = & curl.exe -ksS `
            -u "elastic:$password" `
            "https://127.0.0.1:$LocalElasticsearchPort/logstash-dockerelk-infra-*/_search?q=$query" `
            2>$null

        if ($LASTEXITCODE -eq 0 -and $response) {
            $result = $response | ConvertFrom-Json
            if ([int]$result.hits.total.value -ge 1) {
                Write-Host "Evenement indexe dans Elasticsearch : $eventId"
                break
            }
        }
    } while ((Get-Date) -lt $deadline)

    if ($null -eq $result -or [int]$result.hits.total.value -lt 1) {
        throw "Evenement non retrouve dans Elasticsearch : $eventId"
    }

    $kibanaStatus = & curl.exe -ksS `
        -u "elastic:$password" `
        "https://${NodeIp}:30601/api/status"
    if ($LASTEXITCODE -ne 0) {
        throw "Kibana n'est pas joignable via le NodePort 30601."
    }
    $status = $kibanaStatus | ConvertFrom-Json
    Write-Host "Kibana : $($status.status.overall.level)"
}
finally {
    if ($portForward -and -not $portForward.HasExited) {
        Stop-Process -Id $portForward.Id -Force
    }
    $password = $null
}
