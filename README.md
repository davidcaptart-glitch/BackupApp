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

## Privacidad
BackupApp no envía datos personales ni estadísticas de uso. Solo se conecta a Internet para:
- **Buscar actualizaciones:** una vez al día consulta las versiones publicadas en GitHub y, si aceptas, descarga la nueva. Se puede desactivar: clic derecho en el escudo > «Buscar actualizaciones automáticamente».
- **La nube directa**, si la activas: descarga rclone desde rclone.org y sube tu copia solo a la cuenta que tú conectes, cifrada si lo eliges.

Tus ajustes e historiales se quedan en tu PC (`%LOCALAPPDATA%\BackupApp`). El instalador muestra este aviso antes de instalar.

## Code signing policy (política de firma de código)
Free code signing provided by [SignPath.io](https://about.signpath.io), certificate by [SignPath Foundation](https://signpath.org).

- Los instaladores y el programa se compilan en GitHub Actions a partir de este repositorio ([publicar.yml](.github/workflows/publicar.yml)) y solo se firman esas compilaciones.
- Autores y revisores (committers and reviewers): [davidcaptart-glitch](https://github.com/davidcaptart-glitch)
- Aprobación de cada firma (approvers): [davidcaptart-glitch](https://github.com/davidcaptart-glitch)
- Privacidad: ver la sección anterior. Este programa no transfiere información a otros sistemas salvo que el usuario lo pida expresamente (actualizaciones y nube directa, que se pueden desactivar).

## Licencia
BackupApp es software libre: puedes redistribuirlo y modificarlo bajo los términos de la [Licencia Pública General de GNU, versión 3](LICENSE) (GPL-3.0). Se distribuye sin ninguna garantía.

rclone, que BackupApp descarga solo si activas la nube directa, es un programa independiente con licencia MIT ([rclone.org](https://rclone.org)).