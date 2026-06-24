param(
    [string]$Kubeconfig = (Join-Path $PSScriptRoot "..\kubeconfig"),
    [string]$Kubectl = (Join-Path $HOME "kubectl.exe"),
    [string]$Overlay = (Join-Path $PSScriptRoot "..\..\..\kubernetes\overlays\lab-k3s"),
    [string]$EckVersion = "3.4.0",
    [string]$Namespace = "dockerelk",
    [int]$TimeoutSeconds = 900,
    [switch]$SkipEckOperator,
    [switch]$SkipIntegrationTest,
    [switch]$SkipDemoData
)

$ErrorActionPreference = "Stop"

function Invoke-Kubectl {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    & $Kubectl --kubeconfig $Kubeconfig @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl a echoue : $($Arguments -join ' ')"
    }
}

function Wait-EckResource {
    param(
        [string]$Kind,
        [string]$Name,
        [scriptblock]$Ready,
        [string]$Description
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $json = & $Kubectl --kubeconfig $Kubeconfig `
            -n $Namespace get $Kind $Name -o json 2>$null

        if ($LASTEXITCODE -eq 0 -and $json) {
            $resource = $json | ConvertFrom-Json
            if (& $Ready $resource) {
                Write-Host "[OK] $Description"
                return
            }
        }

        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)

    Invoke-Kubectl -n $Namespace get $Kind $Name --output=yaml
    Invoke-Kubectl -n $Namespace get pods --output=wide
    throw "Timeout : $Description"
}

function Set-LabIndexPolicy {
    $encodedPassword = & $Kubectl --kubeconfig $Kubeconfig `
        -n $Namespace get secret dockerelk-es-elastic-user `
        -o jsonpath="{.data.elastic}"
    if ($LASTEXITCODE -ne 0 -or -not $encodedPassword) {
        throw "Mot de passe elastic introuvable."
    }
    $password = [Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String($encodedPassword)
    )

    $localPort = 19200
    $templateFile = Join-Path $env:TEMP "dockerelk-index-template.json"
    $settingsFile = Join-Path $env:TEMP "dockerelk-index-settings.json"
    Set-Content -Path $templateFile -Encoding ascii -Value (
        '{"index_patterns":["logstash-dockerelk-infra-*"],' +
        '"template":{"settings":{"number_of_shards":1,' +
        '"number_of_replicas":0}}}'
    )
    Set-Content -Path $settingsFile -Encoding ascii -Value (
        '{"index":{"number_of_replicas":0}}'
    )

    $portForward = Start-Process `
        -FilePath $Kubectl `
        -ArgumentList @(
            "--kubeconfig", $Kubeconfig,
            "-n", $Namespace,
            "port-forward",
            "service/dockerelk-es-http",
            "${localPort}:9200"
        ) `
        -PassThru `
        -WindowStyle Hidden

    try {
        Start-Sleep -Seconds 3
        & curl.exe -ksS `
            -u "elastic:$password" `
            -H "Content-Type: application/json" `
            -X PUT `
            "https://127.0.0.1:$localPort/_index_template/dockerelk-infra" `
            --data-binary "@$templateFile" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Creation du template d'index impossible."
        }

        $indices = & curl.exe -ksS `
            -u "elastic:$password" `
            "https://127.0.0.1:$localPort/_cat/indices/logstash-dockerelk-infra-*?h=index"
        if ($LASTEXITCODE -ne 0) {
            throw "Lecture des indices impossible."
        }

        if ($indices.Trim()) {
            & curl.exe -ksS `
                -u "elastic:$password" `
                -H "Content-Type: application/json" `
                -X PUT `
                "https://127.0.0.1:$localPort/logstash-dockerelk-infra-*/_settings" `
                --data-binary "@$settingsFile" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Mise a jour des replicas impossible."
            }
        }
    }
    finally {
        if ($portForward -and -not $portForward.HasExited) {
            Stop-Process -Id $portForward.Id -Force
        }
        Remove-Item $templateFile, $settingsFile `
            -Force `
            -ErrorAction SilentlyContinue
        $password = $null
    }
}

if (-not (Test-Path $Kubeconfig)) {
    throw "Kubeconfig introuvable : $Kubeconfig"
}
if (-not (Test-Path $Kubectl)) {
    throw "kubectl introuvable : $Kubectl"
}
if (-not (Test-Path $Overlay)) {
    throw "Overlay Kubernetes introuvable : $Overlay"
}

Write-Host "[1/8] Preflight Kubernetes"
$nodes = (& $Kubectl --kubeconfig $Kubeconfig get nodes -o json) |
    ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw "Le cluster Kubernetes n'est pas joignable."
}

$nodeItems = @($nodes.items)
if ($nodeItems.Count -ne 3) {
    throw "Trois noeuds sont requis, detectes : $($nodeItems.Count)."
}
foreach ($node in $nodeItems) {
    $ready = $node.status.conditions |
        Where-Object { $_.type -eq "Ready" } |
        Select-Object -First 1
    if ($null -eq $ready -or $ready.status -ne "True") {
        throw "Le noeud $($node.metadata.name) n'est pas Ready."
    }
}

$storageClass = & $Kubectl --kubeconfig $Kubeconfig `
    get storageclass local-path -o name 2>$null
if ($LASTEXITCODE -ne 0 -or -not $storageClass) {
    throw "La StorageClass local-path est requise."
}

if (-not $SkipEckOperator) {
    Write-Host "[2/8] Installation ECK $EckVersion"
    Invoke-Kubectl apply --server-side --force-conflicts `
        -f "https://download.elastic.co/downloads/eck/$EckVersion/crds.yaml"
    Invoke-Kubectl apply --server-side --force-conflicts `
        -f "https://download.elastic.co/downloads/eck/$EckVersion/operator.yaml"
    Invoke-Kubectl -n elastic-system rollout status `
        statefulset/elastic-operator `
        "--timeout=$($TimeoutSeconds)s"
}
else {
    Write-Host "[2/8] Installation ECK ignoree"
}

Write-Host "[3/8] Application des manifests Elastic Stack"
Invoke-Kubectl apply --server-side --force-conflicts -k $Overlay

Write-Host "[4/8] Attente Elasticsearch"
Wait-EckResource `
    -Kind elasticsearch `
    -Name dockerelk `
    -Description "Elasticsearch est disponible" `
    -Ready {
        param($resource)
        $resource.status.health -in @("green", "yellow") -and
        [int]$resource.status.availableNodes -eq 1 -and
        [int]$resource.status.observedGeneration -eq
            [int]$resource.metadata.generation
    }

Set-LabIndexPolicy
Wait-EckResource `
    -Kind elasticsearch `
    -Name dockerelk `
    -Description "Elasticsearch est vert avec zero replique en lab" `
    -Ready {
        param($resource)
        $resource.status.health -eq "green" -and
        [int]$resource.status.availableNodes -eq 1
    }

Write-Host "[5/8] Attente Kibana"
Wait-EckResource `
    -Kind kibana `
    -Name dockerelk `
    -Description "Kibana est vert avec une instance disponible" `
    -Ready {
        param($resource)
        $resource.status.health -eq "green" -and
        [int]$resource.status.availableNodes -eq 1 -and
        [int]$resource.status.observedGeneration -eq
            [int]$resource.metadata.generation
    }

Write-Host "[6/8] Attente Logstash"
Wait-EckResource `
    -Kind logstash `
    -Name dockerelk `
    -Description "Logstash dispose d'une instance" `
    -Ready {
        param($resource)
        [int]$resource.status.availableNodes -eq 1 -and
        [int]$resource.status.observedGeneration -eq
            [int]$resource.metadata.generation
    }

Invoke-Kubectl -n $Namespace get "elasticsearch,kibana,logstash"
Invoke-Kubectl -n $Namespace get "pods,pvc,services" --output=wide

if (-not $SkipIntegrationTest) {
    Write-Host "[7/8] Test d'integration"
    & (Join-Path $PSScriptRoot "Test-ElasticStack.ps1") `
        -Kubeconfig $Kubeconfig `
        -Kubectl $Kubectl
    if ($LASTEXITCODE -ne 0) {
        throw "Le test d'integration Elastic Stack a echoue."
    }
}
else {
    Write-Host "[7/8] Test d'integration ignore"
}

if (-not $SkipDemoData) {
    Write-Host "[8/8] Donnees et dashboard de demonstration"
    & (Join-Path $PSScriptRoot "Seed-ElasticDemo.ps1") `
        -Kubeconfig $Kubeconfig `
        -Kubectl $Kubectl
    if ($LASTEXITCODE -ne 0) {
        throw "La creation de la demonstration Kibana a echoue."
    }
}
else {
    Write-Host "[8/8] Demonstration Kibana ignoree"
}

Write-Host "Elastic Stack deployee et validee."
Write-Host "Kibana : https://<IP_NOEUD>:30601"
Write-Host "Logstash TCP JSON : <IP_NOEUD>:30514"
