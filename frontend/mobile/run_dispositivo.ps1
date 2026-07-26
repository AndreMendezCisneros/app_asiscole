# Lanza la app en un celular físico apuntando al backend local.
# Ajusta la IP si `ipconfig` muestra otra en Ethernet/Wi-Fi.
$ErrorActionPreference = "Stop"
$ip = "192.168.18.206"
Set-Location $PSScriptRoot
flutter run --dart-define="API_BASE_URL=http://${ip}:8000/v0.1" @args
