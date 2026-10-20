# ============================================================
#  Mide el tamano de cada carpeta y de cada "unidad" de reparto.
#  - historial_tamanos.csv : una fila por carpeta y dia (evolucion)
#  - tamanos_unidades.csv  : ultimo tamano de cada unidad (reparto entre discos)
#  Lo lanza el icono una vez al dia con prioridad minima.
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot "config.ps1")
[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'Idle'

$hoy = Get-Date -Format "yyyy-MM-dd"
$totales = @{}
$unidadesFilas = @()
foreach ($u in (UnidadesActuales)) {
    $a = if ($u.Tipo -eq 'sueltos') { Analizar $u.Carpeta.Origen -SoloRaiz } else { Analizar $u.Clave }
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
        $a = Analizar $_.FullName; $totales[$c.Origen][0] += $a.Bytes; $totales[$c.Origen][1] += $a.Archivos }
}
$unidadesFilas | Export-Csv $FicheroUnidades -Delimiter ';' -NoTypeInformation -Encoding UTF8

$filas = @()
if (Test-Path $Historial) { $filas = @(Import-Csv $Historial -Delimiter ';' | Where-Object { $_.Fecha -ne $hoy }) }
foreach ($k in $totales.Keys) {
    $filas += [pscustomobject]@{ Fecha = $hoy; Carpeta = $k; Bytes = $totales[$k][0]; Archivos = $totales[$k][1] }
}
$filas | Export-Csv $Historial -Delimiter ';' -NoTypeInformation -Encoding UTF8
