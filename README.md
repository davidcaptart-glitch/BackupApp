# BackupApp

Copias de seguridad automáticas de tus carpetas a uno o varios discos externos, con un icono en la bandeja de Windows.

- Un asistente te sugiere qué carpetas copiar, mide cuánto ocupan y te recomienda qué discos usar.
- Si no cabe todo, copia antes lo imprescindible y te dice qué disco comprar para el resto.
- Copia solo lo que ha cambiado, comprime en NTFS y reparte las carpetas entre tus discos.
- Reconoce cada disco aunque cambie de letra o lo conectes en otro PC.
- Tema claro u oscuro, y avisos de Windows cuando toca hacer copia.
- Se actualiza solo: te enseña las novedades de cada versión antes de instalarla.

## Instalar
Descarga `BackupApp-setup-X.Y.Z.exe` de la última [release](https://github.com/davidcaptart-glitch/BackupApp/releases/latest) y ejecútalo. No hace falta ser administrador. Al terminar se abre el asistente.

Necesita Windows 10 u 11.

## Desarrollo
- `herramientas\compilar.ps1`: compila `BackupApp.exe` y deja el programa en `dist\BackupApp`.
- `herramientas\publicar.ps1`: crea el instalador (Inno Setup 6) y lo publica en GitHub Releases. Antes hay que subir `VERSION` y añadir sus novedades a `CHANGELOG.md`.
- `src\asistente.ps1` se puede abrir solo para probarlo: `powershell -STA -File src\asistente.ps1`.