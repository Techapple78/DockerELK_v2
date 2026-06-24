$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$moduleRoot = Join-Path $repoRoot "infra\k3s-vsphere"

$requiredFiles = @(
    "terraform\versions.tf",
    "terraform\providers.tf",
    "terraform\variables.tf",
    "terraform\main.tf",
    "terraform\outputs.tf",
    "terraform\terraform.tfvars.example",
    "terraform\cloud-init\server.yaml.tpl",
    "terraform\cloud-init\agent.yaml.tpl",
    "argocd\install.sh",
    "argocd\dockerelk-project.yaml",
    "scripts\Get-Kubeconfig.ps1",
    "scripts\Test-Cluster.ps1",
    "README.md"
)

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $moduleRoot $relativePath
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "Fichier requis absent : $relativePath"
    }
}

$main = Get-Content -Raw (Join-Path $moduleRoot "terraform\main.tf")
$variables = Get-Content -Raw (Join-Path $moduleRoot "terraform\variables.tf")
$serverCloudInit = Get-Content -Raw (
    Join-Path $moduleRoot "terraform\cloud-init\server.yaml.tpl"
)
$agentCloudInit = Get-Content -Raw (
    Join-Path $moduleRoot "terraform\cloud-init\agent.yaml.tpl"
)
$argoInstall = Get-Content -Raw (Join-Path $moduleRoot "argocd\install.sh")

$contracts = @{
    "personnalisation IP statique vSphere" = $main -match "ipv4_address\s*=\s*each\.value\.ipv4_address"
    "control-plane obligatoire" = $variables -match 'contains\(keys\(var\.nodes\), "k3s-server-1"\)'
    "version K3s explicite serveur" = $serverCloudInit -match "INSTALL_K3S_VERSION="
    "version K3s explicite agent" = $agentCloudInit -match "INSTALL_K3S_VERSION="
    "adresse statique du serveur pour les agents" = $agentCloudInit -match 'https://\$\{server_ip\}:6443'
    "version Argo CD obligatoire" = $argoInstall -match 'Usage: \$0 vX\.Y\.Z'
    "aucun manifeste Argo CD stable flottant" = $argoInstall -notmatch '/stable/'
}

$failures = @($contracts.GetEnumerator() | Where-Object { -not $_.Value })
if ($failures.Count -gt 0) {
    $labels = $failures.Name -join ", "
    throw "Contrats non respectes : $labels"
}

Write-Host "Module k3s-vsphere valide : $($requiredFiles.Count) fichiers et $($contracts.Count) contrats."
