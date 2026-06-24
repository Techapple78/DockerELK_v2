param(
    [string]$Kubeconfig = (Join-Path $PSScriptRoot "..\kubeconfig"),
    [string]$Kubectl = (Join-Path $HOME "kubectl.exe"),
    [int]$LocalPort = 5601
)

$ErrorActionPreference = "Stop"

Write-Host "Kibana : https://localhost:$LocalPort"
Write-Host "Dashboard : https://localhost:$LocalPort/app/dashboards#/view/dockerelk-infra-overview"
Write-Host "Laisser ce terminal ouvert. Ctrl+C pour arreter le tunnel."

& $Kubectl --kubeconfig $Kubeconfig `
    -n dockerelk `
    port-forward `
    service/dockerelk-kb-http `
    "${LocalPort}:5601"
