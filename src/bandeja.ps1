# ============================================================
#  BACKUP - icono en la bandeja del sistema (segundo plano)
#  - Vigila tus carpetas por eventos de Windows (no escanea: ~0% CPU)
#  - Detecta los discos de backup al conectarlos (por su marca, no por la letra)
#  - Ofrece registrar discos nuevos y reparte las carpetas entre ellos
#  - Mide el tamano de las carpetas una vez al dia
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'

$mutex = New-Object System.Threading.Mutex($false, "BackupMensualBandeja")
if (-not $mutex.WaitOne(0)) { exit }

. (Join-Path $PSScriptRoot "config.ps1")
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic
. (Join-Path $PSScriptRoot "ui.ps1")
. (Join-Path $PSScriptRoot "asistente.ps1")
. (Join-Path $PSScriptRoot "actualizar.ps1")
. (Join-Path $PSScriptRoot "optimizar.ps1")
[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'Idle'

$ScriptBackup = Join-Path $PSScriptRoot "backup_mensual.ps1"
$ScriptMedir  = Join-Path $PSScriptRoot "medir_tamanos.ps1"
if (Test-Path -LiteralPath $FicheroSalir) { Remove-Item -LiteralPath $FicheroSalir -Force }

# Cambios pendientes: ruta -> unidad de reparto
$script:pend = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
if (Test-Path $FicheroPend) {
    foreach ($l in [IO.File]::ReadAllLines($FicheroPend)) { $p = $l.Split('|'); if ($p.Count -eq 2) { $script:pend[$p[1]] = $p[0] } }
}
$script:sucio = $false; $script:desbordado = $false; $script:ticks = 0
$script:ultimoRecordatorio = [datetime]::MinValue
$script:copiaNube = $false; $script:intentoNube = [datetime]::MinValue
$script:accionClic = $null
$script:proceso = $null; $script:medidor = $null; $script:medidorAntes = $false
$script:intentoMedicion = [datetime]::MinValue
$script:formTam = $null
$script:letrasAntes = @(UnidadesDeDisco | ForEach-Object { $_.Name.Substring(0, 2) })
$script:discosCache = @(LeerDiscos)
$script:marcaDiscos = if (Test-Path $FicheroDiscos) { (Get-Item $FicheroDiscos).LastWriteTime } else { $null }
$patronExcluir = '\\(' + (($Excluir | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')(\\|$)'

# ---------- Utilidades ----------
function FmtTam($b) {
    if ($null -eq $b) { return "-" }
    $a = [math]::Abs([double]$b)
    if ($a -ge 1TB) { "{0:N2} TB" -f ($b / 1TB) } elseif ($a -ge 1GB) { "{0:N1} GB" -f ($b / 1GB) } else { "{0:N0} MB" -f ($b / 1MB) }
}
function FmtDif($b) {
    if ($null -eq $b) { return "-" }
    $signo = if ($b -ge 0) { "+" } else { "-" }
    $signo + (FmtTam ([math]::Abs([double]$b)))
}
function Avisar($titulo, $texto, $accion) {
    $script:accionClic = $accion
    $icono.ShowBalloonTip(15000, $titulo, $texto, [Windows.Forms.ToolTipIcon]::Info)
}
function Copiando { $script:proceso -and -not $script:proceso.HasExited }
function LanzarCopia([switch]$SoloNube) {
    if (Copiando) { if (-not $SoloNube) { Avisar "Backup" "Ya hay una copia en marcha." $null }; return }
    $modo = if ($SoloNube) { "-SoloNube" } else { "-DesdeBandeja" }
    $script:copiaNube = [bool]$SoloNube -or [bool]@(LeerNubes).Count
    $script:proceso = Start-Process powershell.exe -PassThru -ArgumentList `
        "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$ScriptBackup`" $modo"
    try { $script:proceso.PriorityClass = 'BelowNormal' } catch {}
}

# ---------- Cambios pendientes ----------
function Registrar($ruta) {
    if ($ruta -match $patronExcluir) { return }
    if ($script:pend.Count -ge 50000) { $script:desbordado = $true; return }
    if (-not $script:pend.ContainsKey($ruta)) {
        $u = UnidadDeRuta $ruta
        if ($u) { $script:pend[$ruta] = $u; $script:sucio = $true }
    }
}
function GuardarPend { [IO.File]::WriteAllLines($FicheroPend, [string[]]@($script:pend.GetEnumerator() | ForEach-Object { "$($_.Value)|$($_.Key)" })) }
function PendPorDisco {
    # devuelve hashtable IdDisco -> numero de cambios ('' = carpetas nuevas aun sin disco)
    $rep = LeerReparto; $h = @{}
    foreach ($u in $script:pend.Values) { $id = if ($rep.ContainsKey($u)) { $rep[$u] } else { '' }; $h[$id] = 1 + [int]$h[$id] }
    return $h
}
function NumCambios($idDisco) {
    if ($script:desbordado) { return "muchos" }
    if ($null -eq $idDisco) { return "$($script:pend.Count)" }
    $h = PendPorDisco
    return "$([int]$h[$idDisco] + [int]$h[''])"
}
function DiscosQueTocan { @($script:discosCache | Where-Object { DiscoToca $_ }) }
function TextoEstado {
    $txt = "Cambios sin copiar: $(NumCambios $null)"
    $t = DiscosQueTocan
    if (-not $script:discosCache) { $txt += "  |  Sin discos registrados" }
    elseif ($t) { $txt += "  |  Toca copiar: " + (($t | ForEach-Object { $_.Nombre }) -join ", ") }
    else { $txt += "  |  Todos los discos al dia" }
    return $txt
}
function ActualizarTooltip {
    $t = "Backup: $(NumCambios $null) cambios sin copiar"
    if (DiscosQueTocan) { $t += " - toca copia" }
    if ($t.Length -gt 63) { $t = $t.Substring(0, 63) }
    $icono.Text = $t
    $miEstado.Text = TextoEstado
}

# ---------- Ventana invisible, icono y menu ----------
$form = New-Object Windows.Forms.Form
$form.ShowInTaskbar = $false
$null = $form.Handle

$icono = New-Object Windows.Forms.NotifyIcon
$ficheroIcono = RutaRecurso "BackupApp.ico"
$icono.Icon = if ($ficheroIcono) { New-Object Drawing.Icon $ficheroIcono, 16, 16 } else { [Drawing.SystemIcons]::Shield }
$menu = New-Object Windows.Forms.ContextMenuStrip
function MI($texto) { New-Object Windows.Forms.ToolStripMenuItem $texto }
function SEP { New-Object Windows.Forms.ToolStripSeparator }
$miVersion = MI "BackupApp $Version"; $miVersion.Enabled = $false
$miEstado = MI "Estado"; $miEstado.Enabled = $false
$miCopiar = MI "Hacer copia ahora"
$miDiscos = MI "Discos de backup"
$miTam    = MI "Tamano de las carpetas..."
$miPlan   = MI "Plan de copias..."
$miAsis   = MI "Asistente de configuracion..."
$miLiberar = MI "Liberar espacio..."
$miAnadir = MI "Anadir carpeta..."
$miQuitar = MI "Quitar carpeta"
$miLogs   = MI "Abrir registros"
$miActual = MI "Buscar actualizaciones..."
$miAutoAct = MI "Buscar actualizaciones automáticamente"; $miAutoAct.CheckOnClick = $true
$miSalir  = MI "Salir"
[void]$miDiscos.DropDownItems.Add("(cargando)"); [void]$miQuitar.DropDownItems.Add("(cargando)")
[void]$menu.Items.AddRange(@($miVersion, $miEstado,(SEP), $miCopiar, $miDiscos, $miPlan, $miTam, $miLiberar, (SEP), $miAsis, $miAnadir, $miQuitar, (SEP), $miActual, $miAutoAct, $miLogs, $miSalir))
$icono.ContextMenuStrip = $menu

$miCopiar.add_Click({ LanzarCopia })
$miLogs.add_Click({ New-Item -ItemType Directory -Path $CarpetaLogs -Force | Out-Null; Start-Process explorer.exe $CarpetaLogs })
function Salir { GuardarPend; $icono.Visible = $false; [Windows.Forms.Application]::Exit() }
$miSalir.add_Click({ Salir })
$icono.add_DoubleClick({ Avisar "Estado del backup" (TextoEstado) 'copiar' })
$icono.add_BalloonTipClicked({
    $a = "$script:accionClic"
    if ($a -eq 'copiar')            { LanzarCopia }
    elseif ($a -eq 'tamanos')       { MostrarTamanos }
    elseif ($a -eq 'plan')          { MostrarPlan }
    elseif ($a -eq 'asistente')     { AbrirAsistente }
    elseif ($a -eq 'liberar')       { MostrarLiberarEspacio }
    elseif ($a -eq 'actualizar' -and $script:releaseNueva) { MostrarNovedades $script:releaseNueva }
    elseif ($a -like 'registrar:*') { RegistrarDesdeLetra $a.Substring(10) }
})

# ---------- Discos de backup ----------
function RegistrarDesdeLetra($letra) {
    $dr = New-Object IO.DriveInfo $letra
    if (-not $dr.IsReady) { [void][Windows.Forms.MessageBox]::Show("El disco $letra ya no esta conectado.", $Titulo); return }
    $n = @(LeerDiscos).Count + 1
    $etq = if ($dr.VolumeLabel) { " '$($dr.VolumeLabel)'" } else { "" }
    $nombre = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Disco $letra$etq de $(FmtTam $dr.TotalSize) ($(FmtTam $dr.AvailableFreeSpace) libres).`n`n" +
        "Ponle un nombre para reconocerlo (por ejemplo, lo que escribas en una pegatina):", "Registrar disco de backup", "Backup $n")
    if (-not $nombre) { return }
    if ($dr.DriveFormat -ne 'NTFS') {
        $r = [Windows.Forms.MessageBox]::Show("El disco esta en formato $($dr.DriveFormat): funcionara, pero SIN compresion.`n" +
             "Para comprimir habria que formatearlo en NTFS (borra todo su contenido).`n`nRegistrarlo igualmente?", $Titulo, 'YesNo', 'Warning')
        if ($r -ne 'Yes') { return }
    }
    [void](RegistrarDisco $letra $nombre)
    $script:discosCache = @(LeerDiscos); $script:marcaDiscos = (Get-Item $FicheroDiscos).LastWriteTime
    ActualizarTooltip
    Avisar "Disco '$nombre' registrado" "Las carpetas nuevas se repartiran automaticamente entre tus discos segun su espacio libre. Haz clic para copiar ahora." 'copiar'
}
function OlvidarDisco($id) {
    $d = LeerDiscos | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    $r = [Windows.Forms.MessageBox]::Show("Dejar de usar el disco '$($d.Nombre)'?`n`n" +
         "No se borra nada de el. Sus carpetas se repartiran entre los demas discos en la proxima copia (se copiaran de nuevo).",
         $Titulo, 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    GuardarDiscos @(LeerDiscos | Where-Object { $_.Id -ne $id })
    $rep = LeerReparto
    foreach ($k in @($rep.Keys)) { if ($rep[$k] -eq $id) { $rep.Remove($k) } }
    GuardarReparto $rep
    $script:discosCache = @(LeerDiscos)
    ActualizarTooltip
}
function RenombrarDesdeMenu($id) {
    $d = LeerDiscos | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    $c = DiscosConectados | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    $n = PreguntarNombreDisco $null $d.Nombre $(if ($c) { $c.Letra })
    if (-not $n) { return }
    RenombrarDiscoRegistrado $id $n
    $script:discosCache = @(LeerDiscos); $script:marcaDiscos = (Get-Item $FicheroDiscos).LastWriteTime
}
function OlvidarNube($id) {
    $n = LeerNubes | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    if ((Dialogo $null "Dejar de copiar en $($n.Nombre)" "BackupApp dejará de copiar en la nube. Lo que ya está subido no se borra$(if ($n.Tipo -eq 'rclone') { ' (está en la carpeta BackupApp de tu cuenta)' } else { ": está en $(RutaNube $n)" }); puedes borrarlo tú si quieres liberar espacio." @('Cancelar', 'Dejar de copiar') 'Dejar de copiar') -ne 'Dejar de copiar') { return }
    GuardarNubes @(LeerNubes | Where-Object { $_.Id -ne $id })
}
function MenuDiscos {
    $miDiscos.DropDownItems.Clear()
    $con = @(DiscosConectados)
    foreach ($d in $script:discosCache) {
        $c = $con | Where-Object { $_.Id -eq $d.Id } | Select-Object -First 1
        $estado = if ($c) { "conectado en $($c.Letra)" } else { "no conectado" }
        $ult = if ($d.UltimaCopia) { "copia " + $d.UltimaCopia.Substring(0, 10) } else { "sin copias" }
        $it = MI "$($d.Nombre)  -  $estado  -  $ult"
        if ($c) {
            $ab = MI "Abrir"; $ab.Tag = $c.Raiz; $ab.add_Click({ param($s, $e) Start-Process explorer.exe $s.Tag })
            [void]$it.DropDownItems.Add($ab)
        }
        $rn = MI "Cambiar nombre..."; $rn.Tag = $d.Id; $rn.add_Click({ param($s, $e) RenombrarDesdeMenu $s.Tag })
        [void]$it.DropDownItems.Add($rn)
        $ol = MI "Dejar de usar este disco"; $ol.Tag = $d.Id; $ol.add_Click({ param($s, $e) OlvidarDisco $s.Tag })
        [void]$it.DropDownItems.Add($ol)
        [void]$miDiscos.DropDownItems.Add($it)
    }
    foreach ($n in @(LeerNubes)) {
        $ult = if ($n.UltimaCopia) { "copia " + $n.UltimaCopia.Substring(0, 10) } else { "sin copias" }
        $it = MI "$($n.Nombre) (nube)  -  $(if (NubeDisponible $n) { $ult } else { 'carpeta no encontrada' })"
        if ((NubeDisponible $n) -and $n.Tipo -ne 'rclone') { $ab = MI "Abrir carpeta"; $ab.Tag = (RutaNube $n); $ab.add_Click({ param($s, $e) New-Item -ItemType Directory -Path $s.Tag -Force | Out-Null; Start-Process explorer.exe $s.Tag }); [void]$it.DropDownItems.Add($ab) }
        $ol = MI "Dejar de copiar aquí"; $ol.Tag = $n.Id; $ol.add_Click({ param($s, $e) OlvidarNube $s.Tag }); [void]$it.DropDownItems.Add($ol)
        [void]$miDiscos.DropDownItems.Add($it)
    }
    if ($script:discosCache -or @(LeerNubes)) { [void]$miDiscos.DropDownItems.Add((SEP)) }
    $reg = MI "Registrar disco conectado"
    $cands = @(DiscosCandidatos)
    foreach ($dr in $cands) {
        $l = $dr.Name.Substring(0, 2)
        $etq = if ($dr.VolumeLabel) { " $($dr.VolumeLabel)" } else { "" }
        $x = MI "$l$etq  ($(FmtTam $dr.TotalSize))"; $x.Tag = $l
        $x.add_Click({ param($s, $e) RegistrarDesdeLetra $s.Tag })
        [void]$reg.DropDownItems.Add($x)
    }
    if (-not $cands) { $x = MI "(conecta un disco externo nuevo)"; $x.Enabled = $false; [void]$reg.DropDownItems.Add($x) }
    [void]$miDiscos.DropDownItems.Add($reg)
}

# ---------- Carpetas incluidas ----------
$script:watchers = @()
function IniciarVigilancia {
    foreach ($w in $script:watchers) { $w.EnableRaisingEvents = $false; $w.Dispose() }
    $script:watchers = @()
    foreach ($c in $Carpetas) {
        if (-not (Test-Path -LiteralPath $c.Origen)) { continue }
        $w = New-Object IO.FileSystemWatcher $c.Origen
        $w.IncludeSubdirectories = $true
        $w.InternalBufferSize    = 65536
        $w.NotifyFilter          = [IO.NotifyFilters]'FileName, DirectoryName, LastWrite, Size'
        $w.SynchronizingObject   = $form
        $w.add_Changed({ param($s, $e) Registrar $e.FullPath })
        $w.add_Created({ param($s, $e) Registrar $e.FullPath })
        $w.add_Deleted({ param($s, $e) Registrar $e.FullPath })
        $w.add_Renamed({ param($s, $e) Registrar $e.FullPath })
        $w.add_Error({ $script:desbordado = $true; $script:sucio = $true })
        $w.EnableRaisingEvents   = $true
        $script:watchers += $w
    }
}
function GuardarCarpetas($lista) {
    # $lista: rutas; se conserva la prioridad de las que ya estaban
    EscribirCarpetas @($lista | ForEach-Object { $r = $_; $c = $Carpetas | Where-Object { $_.Origen -eq $r } | Select-Object -First 1
        [pscustomobject]@{ Origen = $r; Prioridad = $(if ($c) { $c.Prioridad } else { PrioridadSugerida $r }) } })
    $script:Carpetas = LeerCarpetas
    IniciarVigilancia
}
function AnadirCarpeta {
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Elige la carpeta que quieres incluir en el backup"
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return }
    $nueva = $dlg.SelectedPath.TrimEnd('\')
    $actuales = @($Carpetas | ForEach-Object { $_.Origen })
    $msg = $null
    if ($nueva -match '^[A-Za-z]:$') { $msg = "No se puede anadir una unidad entera. Elige una carpeta." }
    elseif (Test-Path -LiteralPath (Join-Path $nueva.Substring(0, 3) "$CarpetaBackup\$MarcaDisco")) { $msg = "Esa carpeta esta en un disco de backup." }
    else {
        foreach ($a in $actuales) {
            if (DentroDe $nueva $a) { $msg = "Esa carpeta ya se copia, porque esta dentro de:`n$a"; break }
            if (DentroDe $a $nueva) { $msg = "Esa carpeta contiene otra que ya se copia:`n$a`n`nQuita primero '$a' y vuelve a anadir esta."; break }
        }
    }
    if ($msg) { [void][Windows.Forms.MessageBox]::Show($msg, $Titulo, 'OK', 'Warning'); return }
    GuardarCarpetas ($actuales + $nueva)
    Avisar "Carpeta anadida" "$nueva`nSe repartira entre tus discos y se copiara en la proxima copia." $null
}
function QuitarCarpeta($ruta) {
    $r = [Windows.Forms.MessageBox]::Show("Dejar de copiar esta carpeta?`n`n$ruta`n`nNo se borra nada: las copias que ya existen en los discos se conservan.",
                                          $Titulo, 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    GuardarCarpetas @($Carpetas | ForEach-Object { $_.Origen } | Where-Object { $_ -ne $ruta })
    $rep = LeerReparto
    foreach ($k in @($rep.Keys)) { if (DentroDe $k $ruta) { $rep.Remove($k) } }
    GuardarReparto $rep
    foreach ($k in @($script:pend.Keys)) { if (DentroDe $k $ruta) { [void]$script:pend.Remove($k) } }
    $script:sucio = $true
    Avisar "Carpeta quitada" "$ruta ya no se incluira en el backup." $null
}
function MenuCarpetas {
    $miQuitar.DropDownItems.Clear()
    foreach ($c in $Carpetas) {
        $it = MI $c.Origen; $it.Tag = $c.Origen
        $it.add_Click({ param($s, $e) QuitarCarpeta $s.Tag })
        [void]$miQuitar.DropDownItems.Add($it)
    }
    if (-not $Carpetas) { $x = MI "(ninguna)"; $x.Enabled = $false; [void]$miQuitar.DropDownItems.Add($x) }
}
$miAnadir.add_Click({ AnadirCarpeta })
$menu.add_Opening({ MenuDiscos; MenuCarpetas; ActualizarTooltip; EstiloMenu $menu })

# ---------- Tamanos e historial mes a mes ----------
function LeerHistorial {
    if (-not (Test-Path $Historial)) { return @() }
    @(Import-Csv $Historial -Delimiter ';' | ForEach-Object {
        [pscustomobject]@{ Fecha = [datetime]::ParseExact($_.Fecha, 'yyyy-MM-dd', $null); Carpeta = $_.Carpeta
                           Bytes = [int64]$_.Bytes; Archivos = [int64]$_.Archivos } })
}
function Resumen {
    $h = LeerHistorial
    foreach ($c in $Carpetas) {
        $mis = @($h | Where-Object { $_.Carpeta -eq $c.Origen } | Sort-Object Fecha)
        if (-not $mis) { [pscustomobject]@{ Carpeta = $c.Origen; Actual = $null; Archivos = $null; Mes = $null; Anio = $null; Fecha = $null }; continue }
        $u    = $mis[-1]
        $mes  = $mis | Where-Object { $_.Fecha -le $u.Fecha.AddDays(-30) }  | Select-Object -Last 1
        $anio = $mis | Where-Object { $_.Fecha -le $u.Fecha.AddDays(-365) } | Select-Object -Last 1
        [pscustomobject]@{ Carpeta = $c.Origen; Actual = $u.Bytes; Archivos = $u.Archivos; Fecha = $u.Fecha
                           Mes  = $(if ($mes)  { $u.Bytes - $mes.Bytes }  else { $null })
                           Anio = $(if ($anio) { $u.Bytes - $anio.Bytes } else { $null }) }
    }
}
function EvolucionMensual {
    $h = LeerHistorial
    $filas = @()
    foreach ($c in $Carpetas) {
        $porMes = $h | Where-Object { $_.Carpeta -eq $c.Origen } | Sort-Object Fecha |
                  Group-Object { $_.Fecha.ToString('yyyy-MM') } | ForEach-Object { $_.Group[-1] }
        $prev = $null
        foreach ($m in $porMes) {
            $filas += [pscustomobject]@{ Mes = $m.Fecha.ToString('yyyy-MM'); Carpeta = $c.Origen; Bytes = $m.Bytes
                                         Cambio = $(if ($prev) { $m.Bytes - $prev.Bytes } else { $null }) }
            $prev = $m
        }
    }
    $filas | Sort-Object Mes, Carpeta -Descending
}
function EstadoDiscos {
    $rep = LeerReparto; $tam = LeerTamUnidades; $oc = OcupacionPorDisco $rep $tam
    foreach ($d in (LeerDiscos)) {
        $cap = [int64]$d.Capacidad
        [pscustomobject]@{ Nombre = $d.Nombre; Capacidad = $cap; Asignado = $oc[$d.Id]
                           Uso = $(if ($cap) { 100 * $oc[$d.Id] / $cap } else { $null }); Ultima = $d.UltimaCopia }
    }
}
function MedidorActivo { $script:medidor -and -not $script:medidor.HasExited }
function LanzarMedicion {
    if (MedidorActivo) { return }
    $script:medidor = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList `
        "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptMedir`""
    try { $script:medidor.PriorityClass = 'Idle' } catch {}
    $script:medidorAntes = $true
}
function MedicionTerminada {
    $h = LeerHistorial
    if ($h) {
        $fechas = @($h | Select-Object -ExpandProperty Fecha -Unique | Sort-Object)
        $hoy = $fechas[-1]
        $total = ($h | Where-Object { $_.Fecha -eq $hoy } | Measure-Object Bytes -Sum).Sum
        if ($fechas.Count -ge 2 -and $fechas[-2].ToString('yyyy-MM') -ne $hoy.ToString('yyyy-MM')) {
            $lineas = foreach ($r in (Resumen)) { if ($null -ne $r.Mes) { "$(Split-Path $r.Carpeta -Leaf): $(FmtDif $r.Mes)" } }
            if ($lineas) { Avisar "Cambios de tamano en el ultimo mes" (($lineas -join "`n") + "`nTotal: $(FmtTam $total)") 'tamanos' }
        }
    }
    # Discos que se quedan pequenos
    $llenos = @(EstadoDiscos | Where-Object { $_.Uso -gt 90 })
    $plan = if ($script:discosCache) { PlanDeCopias $script:discosCache (AsignarNuevas) (LeerTamUnidades) } else { $null }
    if ($plan -and $plan.EnEspera -gt 0) {
        Avisar "Hay carpetas sin copia" "$(FmtTam $plan.EnEspera) no caben en tus discos y esperan a uno nuevo. Recomendado: un disco de $(TamComercial $plan.Comprar). Haz clic para ver el plan." 'plan'
    } elseif ($llenos) {
        Avisar "Un disco se esta llenando" ((($llenos | ForEach-Object { "$($_.Nombre): {0:N0} %" -f $_.Uso }) -join "`n") + "`nLas carpetas nuevas iran a los discos con mas espacio.") 'tamanos'
    }
    if ($script:formTam -and $script:formTam.IsVisible) { RellenarTamanos }
}
$XamlTamanos = @"
<Window $VentanaBase Title="Tamaño de las carpetas" Width="940" Height="760" MinWidth="720" MinHeight="520" WindowStartupLocation="CenterScreen">
  <Grid Margin="34,28,34,24">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Tamaño de tus carpetas" FontSize="28" FontWeight="SemiBold" FontFamily="Segoe UI Variable Display, Segoe UI"/>
    <TextBlock x:Name="Info" Grid.Row="1" Foreground="{DynamicResource Texto2}" Margin="0,6,0,16"/>
    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0,0,10,0"><StackPanel x:Name="Contenido"/></ScrollViewer>
    <DockPanel Grid.Row="3" Margin="0,18,0,0">
      <Button x:Name="BtnMedir" Content="Medir ahora" Margin="0,0,8,0"/>
      <Button x:Name="BtnExcel" Content="Abrir el historial en Excel"/>
      <Button x:Name="BtnCerrar" Content="Cerrar" Style="{DynamicResource Primario}" MinWidth="110" HorizontalAlignment="Right"/>
    </DockPanel>
  </Grid>
</Window>
"@
function Seccion($titulo) { $x = Texto $titulo 16 'SemiBold'; $x.Margin = '2,14,0,8'; return $x }
function ChipDif($b, $sufijo) {
    if ($null -eq $b) { return $null }
    $tipo = if ($b -gt 0) { 'aviso' } else { 'acento' }
    return (Chip "$(FmtDif $b) $sufijo" $tipo)
}
function GraficoMensual($filas) {
    # Barras con el total de cada mes (ultimos 12): cada barra es la suma de la ultima medicion de cada carpeta en ese mes
    $meses = @($filas | Group-Object Mes | Sort-Object Name | Select-Object -Last 12 | ForEach-Object { [pscustomobject]@{ Mes = $_.Name; Bytes = [int64](($_.Group | Measure-Object Bytes -Sum).Sum) } })
    if ($meses.Count -lt 2) { return (Texto "La evolución aparecerá cuando haya mediciones de al menos dos meses." 12 'Normal' 'Texto2') }
    $max = [double](($meses | Measure-Object Bytes -Maximum).Maximum); $min = [double](($meses | Measure-Object Bytes -Minimum).Minimum)
    $base = [math]::Max(0.0, $min - ($max - $min) * 0.5)   # para que se noten las diferencias entre meses
    $g = New-Object Windows.Controls.Primitives.UniformGrid; $g.Rows = 1; $g.Height = 170
    $nombres = @('', 'ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic')
    for ($k = 0; $k -lt $meses.Count; $k++) {
        $m = $meses[$k]
        $alto = 20 + 110 * (($m.Bytes - $base) / [math]::Max(1.0, $max - $base))
        $barra = New-Object Windows.Controls.Border; $barra.Height = $alto; $barra.CornerRadius = '4,4,0,0'; $barra.Margin = '6,0,6,0'; $barra.VerticalAlignment = 'Bottom'
        Recurso $barra ([Windows.Controls.Border]::BackgroundProperty) $(if ($k -eq $meses.Count - 1) { 'Acento' } else { 'AcentoSuave' })
        $barra.ToolTip = "$($m.Mes): $(FmtTam $m.Bytes)"
        $valor = Texto (FmtTam $m.Bytes) 10.5 'Normal' 'Texto2'; $valor.HorizontalAlignment = 'Center'; $valor.TextWrapping = 'NoWrap'; $valor.Margin = '0,0,0,4'
        $mes = Texto $nombres[[int]$m.Mes.Substring(5, 2)] 11 'Normal' 'Texto2'; $mes.HorizontalAlignment = 'Center'; $mes.Margin = '0,6,0,0'
        $col = New-Object Windows.Controls.DockPanel; $col.LastChildFill = $false
        [Windows.Controls.DockPanel]::SetDock($mes, 'Bottom'); [Windows.Controls.DockPanel]::SetDock($barra, 'Bottom'); [Windows.Controls.DockPanel]::SetDock($valor, 'Bottom')
        [void]$col.Children.Add($mes); [void]$col.Children.Add($barra); [void]$col.Children.Add($valor)
        [void]$g.Children.Add($col)
    }
    return $g
}
function RellenarTamanos {
    $w = $script:formTam; if (-not $w) { return }
    $c = $w.FindName('Contenido'); $c.Children.Clear()
    $res = @(Resumen)
    $total = [int64](($res | Where-Object { $null -ne $_.Actual } | Measure-Object Actual -Sum).Sum)
    $mes = @($res | Where-Object { $null -ne $_.Mes }); $anio = @($res | Where-Object { $null -ne $_.Anio })
    $fecha = ($res | Where-Object { $_.Fecha } | Sort-Object Fecha | Select-Object -Last 1).Fecha
    $w.FindName('Info').Text = if ($fecha) { "Última medición: $($fecha.ToString('dd/MM/yyyy'))$(if (MedidorActivo) { "   $([char]0x00B7)   Midiendo ahora..." })" } else { "Todavía no hay mediciones. Pulsa «Medir ahora» (tarda unos minutos y va en segundo plano)." }
    $tiles = New-Object Windows.Controls.Primitives.UniformGrid; $tiles.Columns = 3
    foreach ($x in @(@('Total', (FmtTam $total), 'Texto'),
                     @('Cambio en un mes', $(if ($mes) { FmtDif (($mes | Measure-Object Mes -Sum).Sum) } else { '-' }), 'Acento'),
                     @('Cambio en un año', $(if ($anio) { FmtDif (($anio | Measure-Object Anio -Sum).Sum) } else { '-' }), 'Acento'))) {
        $t = Tarjeta (Apilar @((Texto $x[0] 12 'Normal' 'Texto2'), (Texto $x[1] 24 'SemiBold' $x[2]))); $t.Margin = '0,0,8,0'; [void]$tiles.Children.Add($t)
    }
    $tiles.Children[2].Margin = '0'
    [void]$c.Children.Add($tiles)
    [void]$c.Children.Add((Seccion "Evolución mes a mes"))
    [void]$c.Children.Add((Tarjeta (GraficoMensual @(EvolucionMensual))))
    [void]$c.Children.Add((Seccion "Carpetas"))
    foreach ($r in ($res | Sort-Object { [int64]$_.Actual } -Descending)) {
        $chips = New-Object Windows.Controls.WrapPanel; $chips.HorizontalAlignment = 'Right'
        foreach ($ch in @((ChipDif $r.Mes 'en un mes'), (ChipDif $r.Anio 'en un año'))) { if ($ch) { [void]$chips.Children.Add($ch) } }
        $det = "$($r.Carpeta)$(if ($null -ne $r.Archivos) { "   $([char]0x00B7)   {0:N0} archivos" -f $r.Archivos })"
        $info = Apilar @((Texto (Split-Path $r.Carpeta -Leaf) 14 'SemiBold'), (Texto $det 11.5 'Normal' 'Texto2')); $info.Margin = '12,0,12,0'
        $tam = Texto (FmtTam $r.Actual) 15 'SemiBold'; $tam.Margin = '12,0,0,0'
        $f = Fila @((Icono ([string][char]0xE8B7) 18 'Acento'), $info, $chips, $tam) @('Auto', '*', 'Auto', 'Auto')
        [void]$c.Children.Add((Tarjeta $f))
    }
    $dis = @(EstadoDiscos)
    if ($dis) {
        [void]$c.Children.Add((Seccion "Discos de backup"))
        foreach ($d in $dis) {
            $uso = if ($null -ne $d.Uso) { $d.Uso / 100 } else { 0 }
            $info = Apilar @((Texto $d.Nombre 14 'SemiBold'), (Texto "$(FmtTam $d.Asignado) asignados de $(FmtTam $d.Capacidad)   $([char]0x00B7)   $(if ($d.Ultima) { "última copia $($d.Ultima)" } else { 'sin copias aún' })" 11.5 'Normal' 'Texto2'))
            $info.Margin = '12,0,16,0'
            $barra = BarraUso $uso $(if ($uso -gt 0.9) { 'Aviso' } else { 'Acento' }); $barra.Width = 200
            $f = Fila @((Icono ([string][char]0xEDA2) 18 'Acento'), $info, $barra, (Texto $(if ($null -ne $d.Uso) { "{0:N0} %" -f $d.Uso } else { '-' }) 14 'SemiBold')) @('Auto', '*', 'Auto', 'Auto')
            $f.Children[3].Margin = '12,0,0,0'
            [void]$c.Children.Add((Tarjeta $f))
        }
    }
}
function MostrarTamanos {
    if ($script:formTam -and $script:formTam.IsVisible) { RellenarTamanos; [void]$script:formTam.Activate(); return }
    $w = NuevaVentana $XamlTamanos
    $script:formTam = $w
    $w.FindName('BtnMedir').add_Click({ LanzarMedicion; RellenarTamanos })
    $w.FindName('BtnExcel').add_Click({ if (Test-Path $Historial) { Start-Process $Historial } })
    $w.FindName('BtnCerrar').add_Click({ $script:formTam.Close() })
    $w.add_Closed({ $script:formTam = $null })
    RellenarTamanos
    MostrarSinBloquear $w
}$miTam.add_Click({ MostrarTamanos })

# ---------- Plan de copias ----------
$XamlPlan = @"
<Window $VentanaBase Title="Plan de copias" Width="840" Height="700" MinWidth="640" MinHeight="480" WindowStartupLocation="CenterScreen">
  <Grid Margin="34,28,34,24">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Plan de copias" FontSize="28" FontWeight="SemiBold" FontFamily="Segoe UI Variable Display, Segoe UI"/>
    <TextBlock x:Name="Desc" Grid.Row="1" Foreground="{DynamicResource Texto2}" Margin="0,6,0,18" TextWrapping="Wrap" Text="Qué se copia en cada disco y qué espera a un disco nuevo."/>
    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0,0,10,0"><StackPanel x:Name="ListaPlan"/></ScrollViewer>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
      <Button x:Name="BtnAsis" Content="Cambiar el plan" Margin="0,0,8,0"/>
      <Button x:Name="BtnCerrar" Content="Cerrar" Style="{DynamicResource Primario}" MinWidth="110"/>
    </StackPanel>
  </Grid>
</Window>
"@
function MostrarPlan {
    $w = NuevaVentana $XamlPlan
    $w.FindName('BtnCerrar').add_Click({ param($s, $e) [Windows.Window]::GetWindow($s).Close() })
    $w.FindName('BtnAsis').add_Click({ param($s, $e) [Windows.Window]::GetWindow($s).Close(); AbrirAsistente })
    $w.Cursor = [Windows.Input.Cursors]::Wait
    MostrarSinBloquear $w
    $discos = @(LeerDiscos)
    $rep = if ($discos) { AsignarNuevas } else { LeerReparto }
    $con = @(DiscosConectados)
    $info = foreach ($d in $discos) {
        $c = $con | Where-Object { $_.Id -eq $d.Id } | Select-Object -First 1
        $ult = if ($d.UltimaCopia) { "última copia $($d.UltimaCopia.Substring(0, 10))" } else { "sin copias aún" }
        [pscustomobject]@{ Id = $d.Id; Detalle = "$(if ($c) { "conectado en $($c.Letra)" } else { 'no conectado' })  $([char]0x00B7)  $ult" }
    }
    $unidades = @(UnidadesActuales); $tam = TamanosDe $unidades
    $np = @(foreach ($n in @(LeerNubes | Where-Object { NubeDisponible $_ })) { $n | Add-Member -NotePropertyName Activa -NotePropertyValue $(if ($n.Tipo -eq 'rclone') { $true } else { NubeActiva $n.Proveedor }) -Force; [pscustomobject]@{ Nube = $n; P = (UnidadesParaNube $n $unidades $tam) } })
    PintarPlan $w.FindName('ListaPlan') (PlanDeCopias $discos $rep $tam) 0 $info $np
    $w.Cursor = $null
    $script:discosCache = @(LeerDiscos)
}
$miPlan.add_Click({ MostrarPlan })

# ---------- Asistente ----------
function AbrirAsistente { MostrarAsistente 'AsistenteTerminado' }
function AsistenteTerminado {
    $script:Carpetas = LeerCarpetas
    IniciarVigilancia
    foreach ($k in @($script:pend.Keys)) { if (-not ($Carpetas | Where-Object { DentroDe $k $_.Origen })) { [void]$script:pend.Remove($k) } }
    GuardarPend
    $script:discosCache = @(LeerDiscos)
    $script:marcaDiscos = if (Test-Path $FicheroDiscos) { (Get-Item $FicheroDiscos).LastWriteTime } else { $null }
    ActualizarTooltip
    if (@(DiscosConectados)) { Avisar "Plan guardado" "Hay un disco de backup conectado. Haz clic aqui para hacer la primera copia." 'copiar' }
    else { Avisar "Plan guardado" "Conecta tu disco de backup cuando quieras: te avisare para copiar." $null }
}
$miAsis.add_Click({ AbrirAsistente })
$miLiberar.add_Click({ MostrarLiberarEspacio })
$script:revisandoEspacio = $false

# ---------- Actualizaciones ----------
$script:releaseNueva = $null; $script:busquedaManual = $false
$timerAct = New-Object Windows.Forms.Timer; $timerAct.Interval = 500
function IniciarBusqueda([bool]$manual) { $script:busquedaManual = $manual; BuscarEnSegundoPlano; $timerAct.Start() }
$timerAct.add_Tick({
    $r = ResultadoBusqueda
    if (-not $r) { return }
    $timerAct.Stop()
    if (-not $r.Ok) {
        if ($script:busquedaManual) { [void](Dialogo $null "No se pudo comprobar" "No hay conexión o GitHub no responde. Vuelve a intentarlo más tarde.`n`n($($r.Error))") }
        return
    }
    $rel = $r.Release
    if ($rel -and (EsMasNueva $rel.Version)) {
        $script:releaseNueva = $rel
        if ($script:busquedaManual) { MostrarNovedades $rel }
        elseif ($rel.Version -ne (LeerAjuste 'OmitirVersion')) { Avisar "BackupApp $($rel.Version) ya está disponible" "Haz clic aquí para ver las novedades e instalarla." 'actualizar' }
    } elseif ($script:busquedaManual) { [void](Dialogo $null "Tienes la última versión" "BackupApp $Version está al día.") }
})
$miActual.add_Click({ IniciarBusqueda $true })
$miAutoAct.Checked = [bool](LeerAjuste 'ActualizarAuto' $true)
$miAutoAct.add_Click({ GuardarAjuste 'ActualizarAuto' $miAutoAct.Checked })

# ---------- Revision ligera cada 15 s ----------
function Revisar {
    $script:ticks++

    # El instalador o el actualizador piden cerrar el icono sin perder los cambios pendientes
    if (Test-Path -LiteralPath $FicheroSalir) { Remove-Item -LiteralPath $FicheroSalir -Force; $timer.Stop(); Salir; return }

    # a) Medicion diaria de tamanos (10 min despues de arrancar, con prioridad minima)
    if ($script:medidorAntes -and -not (MedidorActivo)) { $script:medidorAntes = $false; MedicionTerminada }
    if (-not (MedidorActivo) -and $script:ticks -ge 40 -and -not (Copiando)) {
        $medidoHoy = (Test-Path $Historial) -and (Get-Item $Historial).LastWriteTime.Date -eq (Get-Date).Date
        if (-not $medidoHoy -and $script:intentoMedicion.Date -lt (Get-Date).Date) { $script:intentoMedicion = Get-Date; LanzarMedicion }
    }

    # a2) Busqueda diaria de actualizaciones (2 minutos despues de arrancar)
    if ($script:ticks -ge 8 -and -not (Copiando) -and [bool](LeerAjuste 'ActualizarAuto' $true) -and (LeerAjuste 'UltimaBusqueda') -ne (Get-Date -Format 'yyyy-MM-dd')) {
        GuardarAjuste 'UltimaBusqueda' (Get-Date -Format 'yyyy-MM-dd'); IniciarBusqueda $false
    }

    # a3) Copia semanal en la nube, sola y en segundo plano (como mucho un intento por hora)
    if ($script:copiaNube -and -not (Copiando)) {
        $script:copiaNube = $false
        $hoy = Get-Date -Format 'yyyy-MM-dd'
        $hechas = @(LeerNubes | Where-Object { "$($_.UltimaCopia)".StartsWith($hoy) })
        if ($hechas) { Avisar "Copia en la nube al día" "$(($hechas | ForEach-Object { $_.Nombre }) -join ', '): ya está en su carpeta y el programa de cada servicio la está subiendo." $null }
    }
    if ($script:ticks -ge 40 -and -not (Copiando) -and ((Get-Date) - $script:intentoNube).TotalMinutes -ge 60) {
        if (@(LeerNubes | Where-Object { (NubeDisponible $_) -and (DiscoToca $_) })) { $script:intentoNube = Get-Date; LanzarCopia -SoloNube }
    }

    # a4) Avisos de optimizacion: una revision rapida al dia (15 min despues de arrancar). Se avisa si el disco del
    #     sistema tiene menos del 10 % libre, o si hay 5 GB o mas que liberar (como mucho una vez por semana).
    if ($script:revisandoEspacio) {
        if (-not $script:busquedaOpt -and -not ($script:opt -and $script:opt.Win.IsVisible)) { $script:revisandoEspacio = $false }
        $r = ResultadoOportunidades
        if ($null -ne $r) {
            $script:revisandoEspacio = $false
            $total = [int64](($r | Measure-Object Bytes -Sum).Sum)
            $sis = @(EstadoUnidades | Where-Object { $_.Letra -eq $env:SystemDrive -and $_.PocoEspacio }) | Select-Object -First 1
            $ult = LeerAjuste 'UltimoAvisoEspacio' '2000-01-01'
            $dias = ((Get-Date) - [datetime]::ParseExact($ult, 'yyyy-MM-dd', $null)).TotalDays
            if (($sis -and $dias -ge 1) -or ($total -ge 5GB -and $dias -ge 7)) {
                GuardarAjuste 'UltimoAvisoEspacio' (Get-Date -Format 'yyyy-MM-dd')
                if ($sis) { Avisar "Queda poco espacio en $($sis.Letra)" "Solo $(FmtTam $sis.Libre) libres. Puedes liberar $(FmtTam $total) sin perder nada importante: haz clic aquí." 'liberar' }
                else { Avisar "Puedes liberar $(FmtTam $total)" "Papelera, temporales, cachés y descargas antiguas. Haz clic para revisarlo; no se borra nada sin preguntar." 'liberar' }
            }
        }
    } elseif ($script:ticks -ge 60 -and -not (Copiando) -and (LeerAjuste 'UltimaRevisionEspacio') -ne (Get-Date -Format 'yyyy-MM-dd')) {
        GuardarAjuste 'UltimaRevisionEspacio' (Get-Date -Format 'yyyy-MM-dd'); $script:revisandoEspacio = $true; BuscarOportunidadesEnSegundoPlano
    }

    # b) Ha terminado la copia de algun disco? -> quitar sus cambios pendientes
    $m = if (Test-Path $FicheroDiscos) { (Get-Item $FicheroDiscos).LastWriteTime } else { $null }
    if ($m -ne $script:marcaDiscos) {
        $script:marcaDiscos = $m
        $nuevos = @(LeerDiscos)
        $copiados = @($nuevos | Where-Object { $n = $_; $v = $script:discosCache | Where-Object { $_.Id -eq $n.Id }; $v -and $n.UltimaCopia -ne $v.UltimaCopia } | ForEach-Object { $_.Id })
        $script:discosCache = $nuevos
        if ($copiados) {
            $rep = LeerReparto
            foreach ($k in @($script:pend.Keys)) {
                $u = $script:pend[$k]
                if (-not $rep.ContainsKey($u) -or $copiados -contains $rep[$u]) { [void]$script:pend.Remove($k) }
            }
            $script:desbordado = $false
            GuardarPend
        }
        $script:sucio = $true
    }
    if ($script:sucio) { ActualizarTooltip }
    if ($script:sucio -and ($script:ticks % 20 -eq 0)) { GuardarPend; $script:sucio = $false }

    # c) Discos conectados / desconectados
    $letras = @(UnidadesDeDisco | ForEach-Object { $_.Name.Substring(0, 2) })
    $nuevas = @($letras | Where-Object { $script:letrasAntes -notcontains $_ })
    $script:letrasAntes = $letras
    if ($nuevas -and -not (Copiando)) {
        $con = @(DiscosConectados | Where-Object { $nuevas -contains $_.Letra })
        if ($con) {
            $txt = ($con | ForEach-Object { "'$($_.Nombre)' ($($_.Letra)): $(NumCambios $_.Id) cambios sin copiar" }) -join "`n"
            Avisar "Disco de backup conectado" "$txt`nHaz clic aqui para copiar ahora." 'copiar'
        } else {
            $cand = @(DiscosCandidatos | Where-Object { $nuevas -contains $_.Name.Substring(0, 2) }) | Select-Object -First 1
            if ($cand) {
                $l = $cand.Name.Substring(0, 2)
                Avisar "Disco nuevo detectado ($l, $(FmtTam $cand.TotalSize))" "Haz clic aqui si quieres usarlo como disco de backup. Las carpetas se repartiran automaticamente." "registrar:$l"
            }
        }
    }

    # d) Recordatorio periodico
    if (Copiando) { return }
    if (((Get-Date) - $script:ultimoRecordatorio).TotalHours -ge $HorasEntreRecordatorios) {
        $toca = DiscosQueTocan
        if (-not $Carpetas) {
            $script:ultimoRecordatorio = Get-Date
            Avisar "Backup sin configurar" "Todavia no has elegido que carpetas copiar. Haz clic aqui para abrir el asistente." 'asistente'
        } elseif (-not $script:discosCache) {
            $script:ultimoRecordatorio = Get-Date
            Avisar "Backup sin configurar" "Conecta un disco externo para registrarlo como disco de backup." $null
        } elseif ($toca) {
            $script:ultimoRecordatorio = Get-Date
            $con = @(DiscosConectados | ForEach-Object { $_.Id })
            $nom = ($toca | ForEach-Object { $_.Nombre }) -join ", "
            if ($toca | Where-Object { $con -contains $_.Id }) { Avisar "Toca la copia de seguridad" "Discos: $nom. Hay uno conectado: haz clic aqui para empezar." 'copiar' }
            else { Avisar "Toca la copia de seguridad" "Conecta: $nom. Tienes $(NumCambios $null) cambios sin copiar." 'copiar' }
        }
    }
}

IniciarVigilancia
$icono.Visible = $true
ActualizarTooltip
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 15000
$timer.add_Tick({ Revisar })
$timer.Start()
# Primera ejecucion: sin carpetas elegidas, se abre el asistente
if (-not $Carpetas) { $script:ultimoRecordatorio = Get-Date; AbrirAsistente }
[GC]::Collect()
[Windows.Forms.Application]::Run()
$mutex.ReleaseMutex()
