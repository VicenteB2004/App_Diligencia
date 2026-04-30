# Notificador

## Configurar API key una sola vez (IDE + CLI)

El buscador usa `GOOGLE_PLACES_API_KEY` si esta definida. Para no escribir
`--dart-define` cada vez:

1. Crea tus archivos locales (si aun no existen):
   - `config/env/dev.local.json`
   - `config/env/release.local.json`
2. Pega tu key en ambos archivos:

```json
{
  "GOOGLE_PLACES_API_KEY": "TU_API_KEY",
  "GOOGLE_STATIC_MAPS_API_KEY": "TU_API_KEY_OTRA"
}
```

`GOOGLE_STATIC_MAPS_API_KEY` se usa para la captura del mapa en el informe.
Si no la defines, el proyecto intenta reutilizar `GOOGLE_PLACES_API_KEY` y, si
Google no responde, usa un fallback automático para que el informe no quede sin mapa.

Los `*.local.json` estan ignorados en Git para no subir secretos.

Archivos de ejemplo versionados:
- `config/env/dev.example.json`
- `config/env/release.example.json`

## Perfil de ejecucion en JetBrains

Se dejo configurado en `.idea/runConfigurations/main_dart.xml` el perfil:

- `main.dart (dev local key)`

Ese perfil ya incluye:

`--dart-define-from-file=config/env/dev.local.json`

## Ejecutar en Windows (manual)

```powershell
Set-Location "C:\Flutter_projects\Notificador"
& "C:\dev\flutter\bin\flutter.bat" run -d windows --dart-define-from-file=config/env/dev.local.json
```

Opcion recomendada para no escribir nada a mano:

```powershell
Set-Location "C:\Flutter_projects\Notificador"
powershell -ExecutionPolicy Bypass -File .\scripts\run_windows_dev.ps1
```

## Generar .exe para distribuir

Opcion recomendada (script):

```powershell
Set-Location "C:\Flutter_projects\Notificador"
powershell -ExecutionPolicy Bypass -File .\scripts\build_windows_release.ps1
```

Opcion directa:

```powershell
Set-Location "C:\Flutter_projects\Notificador"
& "C:\dev\flutter\bin\flutter.bat" build windows --release --dart-define-from-file=config/env/release.local.json
```

Salida del ejecutable:

- `build/windows/x64/runner/Release/notificador.exe`

## Android: clave de Google Maps sin hardcode

Agrega esta linea en `android/local.properties` (archivo local, no se sube):

```properties
GOOGLE_MAPS_ANDROID_API_KEY=TU_API_KEY_ANDROID
```

Alternativa CI/CD: variable de entorno `GOOGLE_MAPS_ANDROID_API_KEY`.

Si no defines key, la app sigue funcionando con fallback de geocodificacion.
Para el mapa del informe, el sistema intenta Google Static Maps primero y luego
usa OpenStreetMap como respaldo para no dejar el PDF vacío.

