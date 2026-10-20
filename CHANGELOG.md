# Cambios

## 0.4.8
- Arreglado: si había una copia en marcha, la actualización no se podía instalar porque la ventana de la copia tenía abierto el icono.

## 0.4.7
- La ventana de la copia muestra el progreso en GB, el archivo que se está copiando, la velocidad y el tiempo que falta (antes solo contaba carpetas y parecía parada en las grandes).
- Copia más rápida en discos duros: copia de dos en dos archivos en vez de ocho, que en discos que no son SSD hacía saltar al cabezal.
- En «Liberar espacio», nueva sección «Ya copiado en tus discos de backup»: subcarpetas sin cambios desde su última copia que puedes borrar del PC. Antes se comprueba que la copia es idéntica y se guarda aparte en el disco (_ARCHIVO).
- Arreglado el mensaje de espacio liberado cuando pasaba de 2 GB.

## 0.4.6
- Mejor reparto cuando no cabe todo: dentro de cada prioridad se empieza por las carpetas pequeñas, así se protegen muchas más carpetas y lo que queda esperando a un disco nuevo son solo las más grandes.

## 0.4.5
- Arreglado: la medición de carpetas podía quedarse parada a mitad (por ejemplo en el 35 %) sin avanzar más.
- Si una subcarpeta no se puede medir (sin permiso o en uso), se apunta y se sigue con las demás.
- Lo que ya está medido se guarda sobre la marcha: si cierras el asistente y lo vuelves a abrir, no se repite.

## 0.4.4
- Al abrir BackupApp desde el menú Inicio se muestra su ventana (el plan de copias, o el asistente si aún no está configurado), aunque ya estuviera funcionando junto al reloj. Antes no pasaba nada.
- Al arrancar Windows y después de actualizarse sigue entrando en silencio, solo con el escudo junto al reloj.

## 0.4.3
- Medir las carpetas es mucho más rápido: ya no recorre las que no se copian (node_modules, entornos de Python, cachés), que pueden tener cientos de miles de archivos.
- Se mide primero lo que has marcado, y de una carpeta en una, para no saturar el disco duro.
- Barra de progreso con porcentaje, gigas contados y la carpeta que se está midiendo en cada momento.

## 0.4.2
- Todas las nubes se conectan directamente desde BackupApp, sin instalar nada: Google Drive, Dropbox, OneDrive, pCloud, Box, MEGA, Proton Drive y Backblaze B2.
- La barra de tareas muestra el icono de BackupApp en sus ventanas (antes salía el de PowerShell).
- Explicación más clara de Amazon Photos e iCloud, que no permiten conectarse desde otros programas.

## 0.4.1
- BackupApp es software libre (licencia GPL-3.0).
- El instalador explica qué hace el programa con Internet (solo actualizaciones y, si la activas, la nube directa) y se compila en GitHub a partir del código.
- Nueva opción en el menú del escudo para desactivar la búsqueda automática de actualizaciones.

## 0.4.0
- Nube directa: conecta tu cuenta de Google Drive, Dropbox, OneDrive, pCloud, Box o Backblaze B2 sin instalar su programa ni ocupar espacio en el PC, y con cifrado opcional (solo tú, con tu contraseña, puedes ver los archivos). Usa rclone, que se descarga la primera vez comprobando que es el original.
- La copia muestra su progreso y se puede detener: lo copiado se conserva y la próxima vez sigue donde se quedó.
- Nuevo diseño para la ventana de tamaños, con gráfico de la evolución mes a mes, y para todos los avisos de la copia.
- Al liberar espacio del PC tras la copia, eliges las carpetas en una lista clara con casillas.

## 0.3.0
- Copia extra en la nube: BackupApp encuentra OneDrive, Google Drive, Dropbox, iCloud, MEGA, pCloud, Proton Drive, Box, Sync.com y Nextcloud, y guarda en su carpeta lo imprescindible que quepa en tu espacio. Se hace sola cada semana.
- También puedes elegir cualquier otra carpeta sincronizada o un NAS.
- Nunca sube a una nube lo que ya está en ella, y te avisa si el programa del servicio no está abierto.
- Amazon Photos: te explica cómo usarlo para tus fotos (con Prime, sin límite y también en RAW).
- Nuevo «Liberar espacio» en el menú del escudo: papelera, temporales, cachés, instaladores y comprimidos antiguos o repetidos en Descargas, node_modules y previas de Lightroom. Tú marcas qué borrar y nada se borra sin confirmar.
- Avisos de optimización: te avisa si el disco del sistema se queda sin sitio o si puedes liberar 5 GB o más (como mucho una vez por semana).

## 0.2.0
- Nuevo asistente de configuración con diseño moderno y tema claro u oscuro: te sugiere qué carpetas copiar, mide su tamaño y recomienda qué discos usar.
- Plan de copias: cada carpeta tiene una prioridad. Si no cabe todo, se copia antes lo imprescindible y el resto espera a un disco nuevo; te dice de qué tamaño comprarlo.
- Frecuencia de copia propuesta para cada disco (semanal o mensual).
- Los discos se reconocen por su nombre también en otros PC, y puedes poner ese nombre como etiqueta de Windows.
- Programa instalable (setup.exe) con logo propio, accesos directos y desinstalador.
- Actualizaciones automáticas: te avisa cuando hay una versión nueva y te enseña sus novedades antes de instalarla.
- Tus datos se guardan aparte del programa, así que las actualizaciones no los tocan.

## 0.1.0
- Versión inicial: icono en la bandeja, varios discos con reparto automático, copia diferencial comprimida, limpieza de carpetas sin uso, historial de tamaños.
