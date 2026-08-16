# Checklist local: APK release + recordatorio de cutover VPS.
# Uso (desde la raíz del repo):
#   .\scripts\ops_local_release.ps1
#
# No tiene SSH al VPS. El cutover JP (2026-07-30) ya se aplicó; ver
#   docs/estado-produccion.md
# Redeploy futuro en el servidor:
#   bash scripts/ops_prod_cutover.sh

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

Write-Host "==> Health actual (VPS Jean Piaget)"
try {
  $h = Invoke-RestMethod "https://jeanpiaget.asiscole.com/canal-api/health" -TimeoutSec 20
  Write-Host ($h | ConvertTo-Json -Compress)
} catch {
  Write-Host "No se pudo consultar health:" $_.Exception.Message
}

Write-Host ""
Write-Host "==> APK release (Firebase + obfuscate)"
Set-Location (Join-Path $repo "frontend\mobile")
& ".\tool\build_apk.ps1"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$apk = Join-Path $repo "frontend\mobile\build\app\outputs\flutter-apk\Asis_Messenger.apk"
Write-Host ""
Write-Host "APK listo:" $apk
Write-Host ""
Write-Host "=== Recordatorio VPS (cutover JP ya hecho; solo si redeployas) ==="
Write-Host "1. Sube codigo a /opt/asiscole-canal"
Write-Host "2. .env: DJANGO_SECURE_SSL_REDIRECT=False, REDIS_*, secret, DEBUG=False"
Write-Host "3. En host ~8 GB: Gunicorn 3x2 / Celery 2 (no defaults Opción B)"
Write-Host "4. bash scripts/ops_prod_cutover.sh"
Write-Host "5. Distribuye este APK; tras rotar SECRET_KEY, borrar datos de la app"
Write-Host ""
Write-Host "Estado: docs/estado-produccion.md"
Write-Host "Load test opcional (staging):"
Write-Host '  k6 run -e BASE_URL=https://HOST/canal-api/v0.1 -e DATA_TOKEN=... scripts/load/k6_canal_100vu.js'
