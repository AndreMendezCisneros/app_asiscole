# Lanza la app en un celular físico apuntando al backend del VPS.
# Para Django local: .\run_dispositivo.ps1 -Local -Ip 192.168.100.6
param(
    [switch]$Local,
    [string]$Ip = "192.168.100.6"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if ($Local) {
    $url = "http://${Ip}:8000/v0.1"
    Write-Host "API local: $url"
} else {
    $url = "https://jeanpiaget.asiscole.com/canal-api/v0.1"
    Write-Host "API VPS: $url"
}

flutter run --dart-define="API_BASE_URL=$url" @args
