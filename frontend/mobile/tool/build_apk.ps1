# Genera el APK release y lo publica como Asiscole_Messenger.apk
# Uso (desde frontend/mobile):
#   .\tool\build_apk.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

& "$PSScriptRoot\ensure_firebase.ps1"

flutter build apk --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$outDir = Join-Path $root "build\app\outputs\flutter-apk"
$src = Join-Path $outDir "app-release.apk"
$dst = Join-Path $outDir "Asiscole_Messenger.apk"

if (-not (Test-Path $src)) {
    Write-Error "No se generó app-release.apk"
}

Copy-Item -Force $src $dst
Write-Host "OK: $dst"
