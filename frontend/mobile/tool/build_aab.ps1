# Genera el App Bundle (.aab) firmado para Google Play.
# Uso (desde frontend/mobile):
#   .\tool\build_aab.ps1
#
# Requisitos:
#   - secrets Firebase (ensure_firebase.ps1 los copia).
#   - android/key.properties + keystore de release. Sin él el build FALLA:
#     firmar con la clave de debug permitiría suplantar la app (ver docs/qa).
#
# Play exige AAB para apps nuevas. El APK de sideload sigue en build_apk.ps1.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

& "$PSScriptRoot\ensure_firebase.ps1"

$keyProps = Join-Path $root "android\key.properties"
if (-not (Test-Path $keyProps)) {
    Write-Error "Falta android/key.properties. Copia key.properties.example y apúntalo al keystore de release."
}

# Los símbolos son imprescindibles: el release va ofuscado, así que sin ellos
# los stack traces de Crashlytics y Play Console son ilegibles.
$symbols = Join-Path $root "build\app\outputs\symbols"
New-Item -ItemType Directory -Force -Path $symbols | Out-Null

flutter build appbundle --release `
  --dart-define=ASISCOLE_ENV=prod `
  --obfuscate `
  --split-debug-info=$symbols
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$aab = Join-Path $root "build\app\outputs\bundle\release\app-release.aab"
if (-not (Test-Path $aab)) {
    Write-Error "No se generó app-release.aab"
}

Write-Host "OK: $aab"
Write-Host "Symbols (subir a Play Console y Crashlytics): $symbols"
Write-Host ""
Write-Host "Crashlytics (Dart ofuscado):"
Write-Host "  firebase crashlytics:symbols:upload --app=<ANDROID_APP_ID> $symbols"
Write-Host ""
Write-Host "Siguiente paso: Play Console -> Produccion -> Crear version -> subir el .aab"
Write-Host "y adjuntar los simbolos de $symbols (Android vitals los necesita)."
