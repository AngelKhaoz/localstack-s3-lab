# Recrea LocalStack con CORS habilitado y restaura el laboratorio.
# Uso:  powershell -ExecutionPolicy Bypass -File .\reparar-dashboard.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "`n== 1/4  Recreando el contenedor ==" -ForegroundColor Cyan
docker compose up -d --force-recreate

Write-Host "`n== 2/4  Esperando a que este saludable ==" -ForegroundColor Cyan
$sano = $false
for ($i = 1; $i -le 24; $i++) {
    Start-Sleep -Seconds 5
    $estado = docker inspect --format '{{.State.Health.Status}}' localstack-s3-lab 2>$null
    Write-Host ("   intento {0,2} : {1}" -f $i, $estado)
    if ($estado -eq "healthy") { $sano = $true; break }
}
if (-not $sano) {
    Write-Host "`nEl contenedor no llego a 'healthy'. Revisa: docker compose logs" -ForegroundColor Red
    exit 1
}

Write-Host "`n== 3/4  Recreando la infraestructura con Terraform ==" -ForegroundColor Cyan
$env:AWS_ACCESS_KEY_ID     = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION    = "us-east-1"
terraform apply -auto-approve

Write-Host "`n== 4/4  Subiendo el archivo de prueba ==" -ForegroundColor Cyan
if (-not (Test-Path .\prueba.txt)) {
    "Archivo de prueba - laboratorio S3 seguro" | Set-Content .\prueba.txt
}
aws --endpoint-url http://localhost:4566 s3 cp .\prueba.txt s3://actividad3-seguro-local/
aws --endpoint-url http://localhost:4566 s3 ls s3://actividad3-seguro-local/

Write-Host "`nListo. Ahora recarga el dashboard con Ctrl+F5." -ForegroundColor Green
