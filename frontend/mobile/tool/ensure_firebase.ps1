# Copia Firebase real desde secrets/ si lib tiene el stub de Git.
# Uso: .\tool\ensure_firebase.ps1   (desde frontend/mobile)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$repo = Split-Path -Parent (Split-Path -Parent $root)
$opts = Join-Path $root "lib\firebase_options.dart"
$gs = Join-Path $root "android\app\google-services.json"
$secOpts = Join-Path $repo "secrets\secrets\firebase_options.dart"
$secGs = Join-Path $repo "secrets\secrets\google-services.json"

function Es-Stub([string]$path) {
  if (-not (Test-Path $path)) { return $true }
  $t = Get-Content $path -Raw
  return ($t -match 'REPLACE_WITH_FIREBASE' -or $t -match 'replace-with-project-id')
}

if (Es-Stub $opts) {
  if (-not (Test-Path $secOpts)) {
    Write-Error "firebase_options.dart es stub y no hay $secOpts"
  }
  Copy-Item -Force $secOpts $opts
  Write-Host "OK: firebase_options.dart restaurado desde secrets"
} else {
  Write-Host "OK: firebase_options.dart ya tiene proyecto real"
}

if (-not (Test-Path $gs)) {
  if (-not (Test-Path $secGs)) {
    Write-Error "Falta google-services.json y no hay $secGs"
  }
  Copy-Item -Force $secGs $gs
  Write-Host "OK: google-services.json copiado desde secrets"
} else {
  Write-Host "OK: google-services.json presente"
}

if (Es-Stub $opts) {
  Write-Error "Sigue siendo stub tras copiar; no construyas el APK asi."
}
