param(
    [Parameter(Mandatory = $true)]
    [string]$ServerIp,

    [string]$SshUser = "ubuntu",

    [string]$IdentityFile = (Join-Path $HOME ".ssh\dockerelk_k3s_user"),

    [string]$OutputPath = (Join-Path $PSScriptRoot "..\kubeconfig")
)

$ErrorActionPreference = "Stop"
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$temporaryPath = "$resolvedOutput.tmp"

try {
    if (-not (Test-Path $IdentityFile)) {
        throw "Cle SSH introuvable : $IdentityFile"
    }

    ssh -i $IdentityFile "${SshUser}@${ServerIp}" "sudo cat /etc/rancher/k3s/k3s.yaml" |
        Set-Content -Path $temporaryPath -Encoding ascii

    if (-not (Test-Path $temporaryPath) -or (Get-Item $temporaryPath).Length -eq 0) {
        throw "Le kubeconfig recupere est vide."
    }

    (Get-Content -Raw $temporaryPath).Replace(
        "https://127.0.0.1:6443",
        "https://${ServerIp}:6443"
    ) | Set-Content -Path $resolvedOutput -Encoding ascii
}
finally {
    Remove-Item -Path $temporaryPath -Force -ErrorAction SilentlyContinue
}

Write-Host "Kubeconfig cree : $resolvedOutput"
Write-Host "`$env:KUBECONFIG='$resolvedOutput'"
