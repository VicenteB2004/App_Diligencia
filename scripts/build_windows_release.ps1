param(
  [string]$DefineFile = "config/env/release.local.json"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $DefineFile)) {
  throw "No existe el archivo de defines: $DefineFile"
}

Write-Host "Compilando release de Windows con defines desde: $DefineFile"
& "C:\dev\flutter\bin\flutter.bat" build windows --release --dart-define-from-file=$DefineFile

if ($LASTEXITCODE -ne 0) {
  throw "Fallo el build de Windows"
}

Write-Host "Build completado. EXE en: build\windows\x64\runner\Release\"

