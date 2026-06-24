param(
    [Parameter(Mandatory = $true)]
    [string]$Kubeconfig,

    [int]$ExpectedNodes = 3
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Kubeconfig)) {
    throw "Kubeconfig introuvable : $Kubeconfig"
}

$nodesJson = kubectl --kubeconfig $Kubeconfig get nodes -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw "kubectl get nodes a echoue."
}

$nodes = @($nodesJson.items)
if ($nodes.Count -ne $ExpectedNodes) {
    throw "Nombre de noeuds inattendu : $($nodes.Count), attendu : $ExpectedNodes."
}

foreach ($node in $nodes) {
    $ready = $node.status.conditions |
        Where-Object { $_.type -eq "Ready" } |
        Select-Object -First 1

    if ($null -eq $ready -or $ready.status -ne "True") {
        throw "Le noeud $($node.metadata.name) n'est pas Ready."
    }
}

kubectl --kubeconfig $Kubeconfig get nodes -o wide
Write-Host "Cluster valide : $ExpectedNodes noeuds Ready."
