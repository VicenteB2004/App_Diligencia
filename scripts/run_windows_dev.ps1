param(
  [string]$DefineFile = "config/env/dev.local.json"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $DefineFile)) {
  throw "No existe el archivo de defines: $DefineFile"
}

Write-Host "Iniciando Windows en modo desarrollo con defines desde: $DefineFile"
& "C:\dev\flutter\bin\flutter.bat" run -d windows --dart-define-from-file=$DefineFile

if ($LASTEXITCODE -ne 0) {
  throw "Fallo la ejecucion de Windows"
}

