$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$kubectl = Join-Path $HOME "kubectl.exe"
$overlay = Join-Path $repoRoot "kubernetes\overlays\lab-k3s"

if (-not (Test-Path $kubectl)) {
    throw "kubectl introuvable : $kubectl"
}

$rendered = & $kubectl kustomize $overlay
if ($LASTEXITCODE -ne 0 -or -not $rendered) {
    throw "Le rendu Kustomize a echoue."
}

$contracts = @{
    "Elasticsearch 9.4.2" = $rendered -match "kind: Elasticsearch" -and
        $rendered -match "version: 9.4.2"
    "Kibana" = $rendered -match "kind: Kibana"
    "Logstash" = $rendered -match "kind: Logstash"
    "PVC local-path" = $rendered -match "storageClassName: local-path"
    "Kibana NodePort" = $rendered -match "nodePort: 30601"
    "Logstash NodePort" = $rendered -match "nodePort: 30514"
    "Namespace dockerelk" = $rendered -match "name: dockerelk"
}

$failures = @($contracts.GetEnumerator() | Where-Object { -not $_.Value })
if ($failures.Count -gt 0) {
    throw "Contrats Kubernetes non respectes : $($failures.Name -join ', ')"
}

Write-Host "Manifests Kubernetes valides : $($contracts.Count) contrats."
