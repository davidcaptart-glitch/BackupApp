# ============================================================
#  Mide el tamano de cada carpeta y de cada "unidad" de reparto.
#  - historial_tamanos.csv : una fila por carpeta y dia (evolucion)
#  - tamanos_unidades.csv  : ultimo tamano de cada unidad (reparto entre discos)
#  Lo lanza el icono una vez al dia con prioridad minima.
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot "config.ps1")
[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'Idle'

# Una sola medicion a la vez, y ninguna durante una copia (leen los mismos discos y la copia va mas lenta)
function MutexLibre($nombre) {
    $m = New-Object System.Threading.Mutex($false, $nombre)
    try { if ($m.WaitOne(0)) { return $m } } catch [Threading.AbandonedMutexException] { return $m }
    return $null
}
$script:mutexMedir = MutexLibre "BackupAppMedir"
if (-not $script:mutexMedir) { exit }
# La copia se mira sin crear su mutex: si se creara aqui, el icono creeria que hay una copia en marcha mientras se mide
$copia = $null
if ([Threading.Mutex]::TryOpenExisting("BackupAppCopia", [ref]$copia)) { $copia.Dispose(); exit }

$hoy = Get-Date -Format "yyyy-MM-dd"
$totales = @{}
$hallados = New-Object 'System.Collections.Generic.List[string]'   # node_modules y previas de Lightroom (para Liberar espacio)
$unidadesFilas = @()
foreach ($u in (UnidadesActuales)) {
    $a = if ($u.Tipo -eq 'sueltos') { Analizar $u.Dir -SoloRaiz } else { Analizar $u.Clave -Hallados $hallados }
    $unidadesFilas += [pscustomobject]@{ Unidad = $u.Clave; Bytes = $a.BytesBackup; Fecha = $hoy }
    $o = $u.Carpeta.Origen
    if (-not $totales.ContainsKey($o)) { $totales[$o] = @([int64]0, [int64]0) }
    $totales[$o][0] += $a.Bytes; $totales[$o][1] += $a.Archivos
}
# Carpetas excluidas de primer nivel (node_modules en la raiz...) tambien cuentan en el tamano real
foreach ($c in $Carpetas) {
    if (-not (Test-Path -LiteralPath $c.Origen)) { continue }
    if (-not $totales.ContainsKey($c.Origen)) { $totales[$c.Origen] = @([int64]0, [int64]0) }
    Get-ChildItem -LiteralPath $c.Origen -Directory -Force | Where-Object { $Excluir -contains $_.Name } | ForEach-Object {
        if ([BackupApp.Medidor4]::Regenerable($_.Name)) { $hallados.Add($_.FullName) }
        $a = Analizar $_.FullName; $totales[$c.Origen][0] += $a.Bytes; $totales[$c.Origen][1] += $a.Archivos }
}
$unidadesFilas | Export-Csv $FicheroUnidades -Delimiter ';' -NoTypeInformation -Encoding UTF8
EscribirJson $FicheroRegenerables ([pscustomobject]@{ Fecha = (Get-Date).ToString('o'); Rutas = @($hallados | Select-Object -Unique) })

$filas = @()
if (Test-Path $Historial) { $filas = @(Import-Csv $Historial -Delimiter ';' | Where-Object { $_.Fecha -ne $hoy }) }
foreach ($k in $totales.Keys) {
    $filas += [pscustomobject]@{ Fecha = $hoy; Carpeta = $k; Bytes = $totales[$k][0]; Archivos = $totales[$k][1] }
}
$filas | Export-Csv $Historial -Delimiter ';' -NoTypeInformation -Encoding UTF8

# Si compras discos de 1 o 2 TB: las carpetas sin disco que ya no caben en uno se dividen por sus subcarpetas
[void](DividirSegunAjuste)
