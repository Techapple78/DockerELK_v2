param(
    [string]$Kubeconfig = (Join-Path $PSScriptRoot "..\kubeconfig"),
    [string]$Kubectl = (Join-Path $HOME "kubectl.exe"),
    [string]$Repository = "https://github.com/Techapple78/DockerELK_v2",
    [string]$Revision = "migration/v1-to-v2-data-refactor"
)

$ErrorActionPreference = "Stop"
$manifest = Join-Path $PSScriptRoot `
    "..\..\..\kubernetes\argocd\dockerelk-application.yaml"
$project = Join-Path $PSScriptRoot "..\argocd\dockerelk-project.yaml"

$rawRepository = $Repository.Replace(
    "https://github.com/",
    "https://raw.githubusercontent.com/"
)
$probeUrl = "$rawRepository/$Revision/kubernetes/overlays/lab-k3s/kustomization.yaml"

try {
    Invoke-WebRequest -UseBasicParsing -Method Head -Uri $probeUrl | Out-Null
}
catch {
    throw "La revision distante ne contient pas encore l'overlay Kubernetes : $probeUrl"
}

& $Kubectl --kubeconfig $Kubeconfig apply -f $project
if ($LASTEXITCODE -ne 0) {
    throw "Creation du projet Argo CD impossible."
}

& $Kubectl --kubeconfig $Kubeconfig apply -f $manifest
if ($LASTEXITCODE -ne 0) {
    throw "Creation de l'application Argo CD impossible."
}

& $Kubectl --kubeconfig $Kubeconfig -n argocd wait `
    --for=jsonpath='{.status.health.status}'=Healthy `
    application/dockerelk-v2 `
    --timeout=600s
if ($LASTEXITCODE -ne 0) {
    throw "L'application Argo CD n'est pas Healthy."
}

& $Kubectl --kubeconfig $Kubeconfig -n argocd get `
    application/dockerelk-v2
