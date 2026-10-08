# Copia Firebase real desde secrets/ si lib tiene el stub de Git.
# Uso: .\tool\ensure_firebase.ps1         (desde frontend/mobile; Android)
#      .\tool\ensure_firebase.ps1 -Ios    (exige además la configuración iOS)

param([switch]$Ios)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$repo = Split-Path -Parent (Split-Path -Parent $root)
$opts = Join-Path $root "lib\firebase_options.dart"
$gs = Join-Path $root "android\app\google-services.json"
$plist = Join-Path $root "ios\Runner\GoogleService-Info.plist"
$secOpts = Join-Path $repo "secrets\secrets\firebase_options.dart"
$secGs = Join-Path $repo "secrets\secrets\google-services.json"
$secPlist = Join-Path $repo "secrets\secrets\GoogleService-Info.plist"

function Es-Stub([string]$path) {
  if (-not (Test-Path $path)) { return $true }
  $t = Get-Content $path -Raw
  return ($t -match 'REPLACE_WITH_FIREBASE' -or $t -match 'replace-with-project-id' -or $t -match 'TU_API_KEY')
}

function Tiene-Ios([string]$path) {
  if (-not (Test-Path $path)) { return $false }
  return ((Get-Content $path -Raw) -match 'TargetPlatform\.iOS')
}

# firebase_options.dart no se versiona (claves reales). Un clon nuevo no lo trae,
# así que se deja el stub para que `flutter analyze` y `flutter test` compilen.
# El release no se salva con esto: más abajo se exige el archivo de secrets.
if (-not (Test-Path $opts)) {
  Copy-Item -Force (Join-Path $root "lib\firebase_options.dart.example") $opts
  Write-Host "OK: firebase_options.dart creado desde el .example (stub)"
}

# Si el de secrets ya trae iOS y el local no, se reemplaza: el local quedó de
# antes de registrar la app iOS en Firebase.
$debeCopiar = (Es-Stub $opts) -or ($Ios -and -not (Tiene-Ios $opts) -and (Tiene-Ios $secOpts))
if ($debeCopiar) {
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

if (-not (Test-Path $plist)) {
  if (Test-Path $secPlist) {
    Copy-Item -Force $secPlist $plist
    Write-Host "OK: GoogleService-Info.plist copiado desde secrets"
  } elseif ($Ios) {
    Write-Error "Falta GoogleService-Info.plist y no hay $secPlist"
  } else {
    Write-Host "AVISO: sin GoogleService-Info.plist (solo hace falta para iOS)"
  }
} else {
  Write-Host "OK: GoogleService-Info.plist presente"
}

if (Es-Stub $opts) {
  Write-Error "Sigue siendo stub tras copiar; no construyas el APK asi."
}

if ($Ios -and -not (Tiene-Ios $opts)) {
  Write-Error "firebase_options.dart no tiene la rama iOS; ejecuta flutterfire configure con iOS."
}
