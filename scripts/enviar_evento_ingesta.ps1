# Envia un evento de prueba a POST /v0.1/ingesta/eventos (sin Celery).
# Uso:
#   .\scripts\enviar_evento_ingesta.ps1
#   .\scripts\enviar_evento_ingesta.ps1 -Tipo salida -IdEstudiante 1 -IdRegistro 999001
#   .\scripts\enviar_evento_ingesta.ps1 -BaseUrl http://192.168.18.206:8000

param(
    [string]$BaseUrl = "http://127.0.0.1:8000",
    [string]$TenantId = "jean_piaget",
    [ValidateSet("entrada", "salida", "incidencia")]
    [string]$Tipo = "entrada",
    [int]$IdEstudiante = 1,
    [int]$IdRegistro = 0,
    [string]$IngestKey = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root ".env"

if (-not $IngestKey -and (Test-Path $envFile)) {
    $line = Get-Content $envFile | Where-Object { $_ -match '^\s*INGEST_API_KEY\s*=' } | Select-Object -First 1
    if ($line) {
        $IngestKey = ($line -split '=', 2)[1].Trim().Trim('"').Trim("'")
    }
}

if (-not $IngestKey) {
    Write-Error "Falta INGEST_API_KEY (.env o -IngestKey)."
}

if ($IdRegistro -le 0) {
    $IdRegistro = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() % 1000000000)
}

$payload = @{
    id_estudiante     = $IdEstudiante
    nombre_completo   = "Estudiante prueba"
    grado             = "1"
    seccion           = "A"
    nivel_educativo   = "Primaria"
    fecha             = (Get-Date -Format "yyyy-MM-dd")
}

switch ($Tipo) {
    "entrada" {
        $payload.hora_llegada = "08:00"
        $payload.estado = "A tiempo"
    }
    "salida" {
        $payload.hora_salida = "13:00"
        $payload.tipo_salida = "Normal"
    }
    "incidencia" {
        $payload.hora = "10:30"
        $payload.nombre_falta = "Tarea incompleta"
        $payload.categoria = "Academica"
        $payload.es_grave = $false
        $payload.nivel_reincidencia = 1
        $payload.observaciones = "Prueba canal"
        $payload.nombre_usuario_registro = "Tutor prueba"
    }
}

$body = @{
    tenant_id     = $TenantId
    tipo          = $Tipo
    id_estudiante = $IdEstudiante
    id_registro   = $IdRegistro
    payload       = $payload
} | ConvertTo-Json -Depth 5

$url = "$BaseUrl/v0.1/ingesta/eventos"
Write-Host "POST $url"
Write-Host "tipo=$Tipo id_estudiante=$IdEstudiante id_registro=$IdRegistro"

try {
    $resp = Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Headers @{
        "X-Asiscole-Ingest-Key" = $IngestKey
    } -Body $body
    Write-Host "OK 202 creados=$($resp.creados) origen=$($resp.origen_evento)"
    $resp | ConvertTo-Json -Compress
} catch {
    Write-Host "FALLO: $($_.Exception.Message)"
    if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message }
    exit 1
}
