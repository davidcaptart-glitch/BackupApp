# ============================================================
#  ASISTENTE DE CONFIGURACION (primera ejecucion y menu del escudo)
#  1. Carpetas: sugiere las habituales y las grandes de otros discos internos, las mide en segundo plano
#     y deja elegir la prioridad de cada una.
#  2. Discos: muestra todas las unidades, reconoce los discos de backup (por su marca) y sugiere cuales usar.
#  3. Plan: simula el reparto con Repartir (config.ps1) sin guardar nada hasta pulsar Finalizar.
#  Interfaz WPF con el estilo de ui.ps1. Se usa desde bandeja.ps1 (dot-source + MostrarAsistente)
#  o suelto para probarlo:  powershell -NoProfile -ExecutionPolicy Bypass -STA -File asistente.ps1
# ============================================================
if (-not (Get-Command LeerCarpetas -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot "config.ps1") }
if (-not (Get-Command NuevaVentana -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot "ui.ps1") }

# Estado del asistente. Va en el ambito del script porque los eventos de WPF no ven las variables locales.
$script:asis = $null
$TextoPrioridad = @{ 1 = 'Imprescindible'; 2 = 'Normal'; 3 = 'Si sobra sitio' }
# Carpetas de primer nivel de otros discos que nunca se sugieren
$NoSugerir = @('Program Files', 'Program Files (x86)', 'Windows', 'ProgramData', 'PerfLogs', 'Recovery', '$WinREAgent',
               'Steam', 'SteamLibrary', 'XboxGames', 'Epic Games', 'Games', 'MSOCache', 'Intel', 'AMD', 'NVIDIA', $CarpetaBackup,
               'WindowsApps', 'WpSystem', 'WUDownloadCache', 'DockerData', 'Docker', 'Config.Msi', 'OneDriveTemp')
# ...ni las que por su nombre son temporales o caches que se regeneran
$PatronNoSugerir = '^\.|pnpm-store|^te?mp(_|$)|cache|^\$'
$GlifoDisco = [string][char]0xEDA2; $GlifoUsb = [string][char]0xE88E; $GlifoCarpeta = [string][char]0xE8B7
$GlifoAviso = [string][char]0xE7BA; $GlifoOk = [string][char]0xE73E; $GlifoCompra = [string][char]0xE7BF

function TamTxt($b) {
    if ($null -eq $b) { return "-" }
    $x = [math]::Abs([double]$b)
    if ($x -ge 1TB) { "{0:N2} TB" -f ($b / 1TB) } elseif ($x -ge 1GB) { "{0:N1} GB" -f ($b / 1GB) } else { "{0:N0} MB" -f ($b / 1MB) }
}
function NombreCorto($ruta) { $n = Split-Path $ruta.TrimEnd('\') -Leaf; if ($n) { $n } else { $ruta } }

# ---------- Paso 1: carpetas ----------
function AgregarCarpetaAsis($ruta, $motivo, $prioridad, $marcada) {
    $ruta = $ruta.TrimEnd('\')
    if ($script:asis.Carpetas.Contains($ruta)) { return }
    $c = [pscustomobject]@{ Origen = $ruta; Destino = (DestinoDe $ruta); Prioridad = $prioridad }
    $o = [pscustomobject]@{ Ruta = $ruta; Motivo = $motivo; Carpeta = $c; Unidades = @(UnidadesDe @($c)); Marcada = $marcada; Check = $null; TxtTam = $null }
    $script:asis.Carpetas[$ruta] = $o
    $falta = @($o.Unidades | Where-Object { -not $script:asis.Tam.ContainsKey($_.Clave) })
    if ($falta) { MedirEnSegundoPlano $falta }
    [void]$script:asis.Lista.Children.Add((TarjetaCarpeta $o))
}
function TarjetaCarpeta($o) {
    $chk = New-Object Windows.Controls.CheckBox; $chk.IsChecked = $o.Marcada; $chk.Tag = $o.Ruta
    $chk.add_Click({ param($s, $e) $script:asis.Carpetas[$s.Tag].Marcada = [bool]$s.IsChecked; RefrescarTamanos })
    $o.Check = $chk
    $det = Texto "$($o.Ruta)   $([char]0x00B7)   $($o.Motivo)" 11.5 'Normal' 'Texto2'; $det.TextWrapping = 'NoWrap'; $det.TextTrimming = 'CharacterEllipsis'; $det.ToolTip = $o.Ruta
    $info = Apilar @((Texto (NombreCorto $o.Ruta) 14 'SemiBold'), $det); $info.Margin = '12,0,12,0'
    $tam = Texto "midiendo..." 13 'SemiBold' 'Texto2'; $tam.HorizontalAlignment = 'Right'; $tam.Margin = '0,0,16,0'; $tam.TextWrapping = 'NoWrap'
    $o.TxtTam = $tam
    $pri = New-Object Windows.Controls.StackPanel; $pri.Orientation = 'Horizontal'
    foreach ($p in 1, 2, 3) {
        $rb = New-Object Windows.Controls.RadioButton; $rb.Style = $script:Estilos['Pastilla']; $rb.Content = $TextoPrioridad[$p]
        $rb.GroupName = "pri_" + $script:asis.Carpetas.Count; $rb.IsChecked = ($o.Carpeta.Prioridad -eq $p); $rb.Tag = "$p|$($o.Ruta)"
        $rb.add_Checked({ param($s, $e) $p, $r = $s.Tag.Split('|', 2); $script:asis.Carpetas[$r].Carpeta.Prioridad = [int]$p })
        [void]$pri.Children.Add($rb)
    }
    $card = Tarjeta (Fila @($chk, $info, $tam, $pri) @('Auto', '*', 'Auto', 'Auto'))
    $card.Padding = '16,10'
    return $card
}
function SugerirCarpetas {
    $primeraVez = -not $Carpetas
    foreach ($c in $Carpetas) { AgregarCarpetaAsis $c.Origen "Ya incluida en el backup" $c.Prioridad $true }
    $habituales = [ordered]@{ MyDocuments = 'Documentos'; Desktop = 'Escritorio'; MyPictures = 'Imágenes'; MyVideos = 'Vídeos'; MyMusic = 'Música' }
    foreach ($k in $habituales.Keys) {
        $r = [Environment]::GetFolderPath($k)
        if (-not $r -or -not (Test-Path -LiteralPath $r)) { continue }
        $motivo = "Carpeta de $($habituales[$k])"
        # En OneDrive ya hay copia en la nube; si hay archivos solo en la nube, copiarlos los descargaria
        if ($env:OneDrive -and (DentroDe $r $env:OneDrive)) { $motivo += " (en OneDrive)" }
        AgregarCarpetaAsis $r $motivo (PrioridadSugerida $r) $primeraVez
    }
    # Carpetas de primer nivel de otros discos internos (D:\...), sin marcar: el usuario decide
    foreach ($i in @(InfoDiscos | Where-Object { -not $_.Sistema -and -not $_.Externo -and -not $_.IdMarca })) {
        Get-ChildItem -LiteralPath "$($i.Letra)\" -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { -not ($_.Attributes -band ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System -bor [IO.FileAttributes]::ReparsePoint)) -and
                           $NoSugerir -notcontains $_.Name -and $_.Name -notmatch $PatronNoSugerir } |
            ForEach-Object { AgregarCarpetaAsis $_.FullName "Carpeta del disco $($i.Letra)" (PrioridadSugerida $_.FullName) $false }
    }
}
function MedirEnSegundoPlano($unidades) {
    # Mide las unidades en otro hilo; los resultados llegan por la cola y los recoge el temporizador
    $trabajo = @($unidades | ForEach-Object { [pscustomobject]@{ Clave = $_.Clave; Tipo = $_.Tipo; Origen = $_.Carpeta.Origen } })
    $ps = [powershell]::Create()
    [void]$ps.AddScript({
        param($config, $trabajo, $cola)
        . $config
        foreach ($u in $trabajo) {
            $a = if ($u.Tipo -eq 'sueltos') { Analizar $u.Origen -SoloRaiz } else { Analizar $u.Clave }
            $cola.Enqueue([pscustomobject]@{ Clave = $u.Clave; Bytes = $a.Bytes; BytesBackup = $a.BytesBackup })
        }
    }.ToString())
    [void]$ps.AddArgument((Join-Path $Codigo "config.ps1")); [void]$ps.AddArgument($trabajo); [void]$ps.AddArgument($script:asis.Cola)
    $script:asis.Trabajos.Add($ps); [void]$ps.BeginInvoke()
}
function MedidaDe($o) {
    $b = [int64]0; $n = 0
    foreach ($u in $o.Unidades) { if ($script:asis.Tam.ContainsKey($u.Clave)) { $b += $script:asis.Tam[$u.Clave]; $n++ } }
    [pscustomobject]@{ Bytes = $b; Medidas = $n; Total = @($o.Unidades).Count; Completa = ($n -ge @($o.Unidades).Count) }
}
function RefrescarTamanos {
    $a = $script:asis; $total = [int64]0; $completo = $true; $n = 0
    foreach ($o in $a.Carpetas.Values) {
        $m = MedidaDe $o
        $o.TxtTam.Text = if ($m.Completa) { TamTxt $m.Bytes } else { "midiendo $($m.Medidas)/$($m.Total)" }
        if ($o.Marcada) { $n++; $total += $m.Bytes; if (-not $m.Completa) { $completo = $false } }
    }
    $a.Win.FindName('TxtTotal').Text = "$n carpetas $([char]0x00B7) $(TamTxt $total)$(if (-not $completo) { ' (midiendo...)' })"
}
function MarcadasAsis { @($script:asis.Carpetas.Values | Where-Object { $_.Marcada }) }
function AnadirCarpetaAsis {
    $r = ElegirCarpeta $script:asis.Win "Elige otra carpeta para incluir en el backup"
    if (-not $r) { return }
    $r = $r.TrimEnd('\')
    if ($r -match '^[A-Za-z]:$') { [void](Dialogo $script:asis.Win "Elige una carpeta" "No se puede añadir una unidad entera. Elige una carpeta dentro de ella."); return }
    if ($script:asis.Carpetas.Contains($r)) { $o = $script:asis.Carpetas[$r]; $o.Marcada = $true; $o.Check.IsChecked = $true; RefrescarTamanos; return }
    AgregarCarpetaAsis $r "Elegida por ti" (PrioridadSugerida $r) $true
    RefrescarTamanos
}
function ValidarCarpetas {
    $m = @(MarcadasAsis)
    if (-not $m) { return "Marca al menos una carpeta." }
    foreach ($x in $m) {
        if (Test-Path -LiteralPath (Join-Path $x.Ruta.Substring(0, 3) "$CarpetaBackup\$MarcaDisco")) { return "$($x.Ruta) está en un disco de backup." }
        foreach ($y in $m) {
            if ($x -ne $y -and (DentroDe $x.Ruta $y.Ruta)) { return "$($x.Ruta) está dentro de $($y.Ruta). Desmarca una de las dos." }
        }
    }
    return $null
}

# ---------- Paso 2: discos ----------
function LlenarDiscos {
    $a = $script:asis; $lista = $a.Win.FindName('ListaDiscos'); $lista.Children.Clear()
    $origenes = @(MarcadasAsis | ForEach-Object { $_.Ruta.Substring(0, 2).ToUpper() })
    $infos = @(InfoDiscos)
    $reg = @(LeerDiscos); $n = $reg.Count
    $a.FilasDiscos = New-Object 'System.Collections.Generic.List[object]'
    foreach ($i in $infos) {
        $t = [pscustomobject]@{ Clave = $i.Letra; Tipo = 'nuevo'; Info = $i; Registro = $i.Registrado; Nombre = $null; Ajeno = $null; Marcar = $false; Estado = @(); TxtNombre = $null }
        if ($i.IdMarca) { $t.Clave = $i.IdMarca }
        if ($i.Sistema) { $t.Tipo = 'bloqueado'; $t.Estado += , @('Disco del sistema: no sirve como backup', 'normal') }
        elseif ($origenes -contains $i.Letra.ToUpper()) { $t.Tipo = 'bloqueado'; $t.Estado += , @('Tiene carpetas que se van a copiar', 'normal') }
        elseif ($i.Registrado) {
            $t.Tipo = 'registrado'; $t.Nombre = $i.Registrado.Nombre; $t.Marcar = $true
            $t.Estado += , @("Disco de backup $([char]0x00B7) $(if ($i.Registrado.UltimaCopia) { 'última copia ' + $i.Registrado.UltimaCopia.Substring(0, 10) } else { 'sin copias aún' })", 'acento')
        }
        elseif ($i.IdMarca) { $t.Marcar = $true; $t.Nombre = $i.NombreMarca; $t.Estado += , @('Ya se usó como backup: se reconoce', 'acento') }
        elseif ($i.Externo) { $t.Marcar = $true; $t.Estado += , @('Recomendado', 'acento') }
        else { $t.Estado += , @('Interno: protege menos que uno externo', 'normal') }
        if ($t.Tipo -ne 'bloqueado') {
            if ($i.Formato -ne 'NTFS') { $t.Estado += , @("$($i.Formato): sin compresión", 'aviso') }
            if (-not $i.IdMarca -and $i.Libre -lt 0.1 * $i.Capacidad) { $t.Estado += , @('Poco espacio libre', 'aviso') }
        }
        if (-not $t.Nombre) { $n++; $t.Nombre = if ($i.Etiqueta) { $i.Etiqueta } else { "Backup $n" } }
        $a.FilasDiscos.Add($t)
    }
    foreach ($r in $reg) {
        if ($infos | Where-Object { $_.IdMarca -eq $r.Id }) { continue }
        $a.FilasDiscos.Add([pscustomobject]@{ Clave = $r.Id; Tipo = 'registrado'; Info = $null; Registro = $r; Nombre = $r.Nombre; Ajeno = $r.Ajeno; Marcar = $true
                                              Estado = @(, @('Disco de backup, ahora no conectado', 'normal')); TxtNombre = $null })
    }
    for ($k = 0; $k -lt $a.FilasDiscos.Count; $k++) {
        $t = $a.FilasDiscos[$k]
        # Lo que el usuario ya decidio en esta sesion del asistente se respeta
        if ($a.Decision.ContainsKey($t.Clave) -and $t.Tipo -ne 'bloqueado') { $t.Marcar = $a.Decision[$t.Clave].Marcar; $t.Nombre = $a.Decision[$t.Clave].Nombre }
        [void]$lista.Children.Add((TarjetaDisco $t $k))
    }
}
function TarjetaDisco($t, $k) {
    $i = $t.Info
    $chk = New-Object Windows.Controls.CheckBox; $chk.IsChecked = $t.Marcar; $chk.Tag = $k; $chk.IsEnabled = ($t.Tipo -ne 'bloqueado')
    $chk.add_Click({ param($s, $e) $t = $script:asis.FilasDiscos[$s.Tag]; $t.Marcar = [bool]$s.IsChecked; $script:asis.Decision[$t.Clave] = @{ Marcar = $t.Marcar; Nombre = $t.Nombre } })
    $ico = Icono $(if ($i -and $i.Externo) { $GlifoUsb } else { $GlifoDisco }) 26 $(if ($t.Tipo -ne 'bloqueado') { 'Acento' } else { 'Texto2' }); $ico.Margin = '14,0,14,0'
    $nombre = Texto $t.Nombre 14 'SemiBold'; $t.TxtNombre = $nombre
    $sub = if ($i) { "$($i.Letra) $($i.Etiqueta)   $([char]0x00B7)   $(if ($i.Externo) { 'externo' } else { 'interno' })   $([char]0x00B7)   $($i.Formato)" } else { "no conectado" }
    $chips = New-Object Windows.Controls.WrapPanel; $chips.Margin = '0,6,0,0'
    foreach ($e in $t.Estado) { [void]$chips.Children.Add((Chip $e[0] $e[1])) }
    $info = Apilar @($nombre, (Texto $sub 11.5 'Normal' 'Texto2'), $chips)
    $cap = [int64]$(if ($i) { $i.Capacidad } else { $t.Registro.Capacidad })
    $uso = if ($i) {
        $u = Apilar @((Texto "$(TamTxt $i.Libre) libres de $(TamTxt $cap)" 12 'Normal' 'Texto2'), (BarraUso (($cap - $i.Libre) / [math]::Max(1.0, [double]$cap)) $(if ($i.Libre -lt 0.1 * $cap) { 'Aviso' } else { 'Acento' })))
        $u.Children[0].Margin = '0,0,0,6'; $u.Width = 210; $u.Margin = '16,0,16,0'; $u
    } else { $x = Texto "$(TamTxt $cap)" 12 'Normal' 'Texto2'; $x.Margin = '16,0,16,0'; $x }
    $ren = $null
    if ($t.Tipo -ne 'bloqueado') {
        $ren = New-Object Windows.Controls.Button; $ren.Style = $script:Estilos['Enlace']; $ren.Content = "Cambiar nombre"; $ren.Tag = $k
        $ren.add_Click({ param($s, $e) RenombrarDisco $s.Tag })
    }
    $card = Tarjeta (Fila @($chk, $ico, $info, $uso, $ren) @('Auto', 'Auto', '*', 'Auto', 'Auto'))
    if ($t.Tipo -eq 'bloqueado') { $card.Opacity = 0.55 }
    return $card
}
function RenombrarDisco($k) {
    $t = $script:asis.FilasDiscos[$k]
    $n = PreguntarNombreDisco $script:asis.Win $t.Nombre $(if ($t.Info) { $t.Info.Letra })
    if (-not $n) { return }
    $t.Nombre = $n
    $script:asis.Decision[$t.Clave] = @{ Marcar = $t.Marcar; Nombre = $n }
    if ($t.Registro) { RenombrarDiscoRegistrado $t.Registro.Id $n }
    LlenarDiscos   # vuelve a leer las unidades por si cambio la etiqueta de Windows
}
function DiscosElegidos {
    foreach ($t in @($script:asis.FilasDiscos | Where-Object { $_.Marcar -and $_.Tipo -ne 'bloqueado' })) {
        $i = $t.Info
        if ($t.Registro) {
            [pscustomobject]@{ Id = $t.Registro.Id; Nombre = $t.Nombre; NombreReal = $t.Nombre; Detalle = $(if ($i) { "$($i.Letra) $([char]0x00B7) registrado" } else { "no conectado" })
                               Capacidad = $t.Registro.Capacidad; Ajeno = $t.Registro.Ajeno; Nuevo = $false; Letra = $(if ($i) { $i.Letra }) }
        } else {
            if ($null -eq $t.Ajeno) { $t.Ajeno = EspacioAjeno $i.Drive }
            [pscustomobject]@{ Id = $(if ($i.IdMarca) { $i.IdMarca } else { "nuevo:$($i.Letra)" }); Nombre = $t.Nombre; NombreReal = $t.Nombre; Detalle = "$($i.Letra) $([char]0x00B7) se registrará al finalizar"
                               Capacidad = $i.Capacidad; Ajeno = $t.Ajeno; Nuevo = $true; Letra = $i.Letra }
        }
    }
}

# ---------- Paso 3: plan ----------
function PintarPlan($panel, $plan, $ahorro = 0, $discosInfo = $null) {
    # Dibuja un plan (PlanDeCopias) con tarjetas. Lo usan el asistente y la ventana "Plan de copias".
    $panel.Children.Clear()
    $asignado = [int64](($plan.Discos | Measure-Object Asignado -Sum).Sum)
    $tiles = New-Object Windows.Controls.Primitives.UniformGrid; $tiles.Columns = 3; $tiles.Margin = '0,0,0,8'
    foreach ($x in @(@('Datos a copiar', (TamTxt $plan.Total), 'Texto'), @('Con disco asignado', (TamTxt $asignado), 'Acento'),
                     @('En espera', (TamTxt $plan.EnEspera), $(if ($plan.EnEspera -gt 0) { 'Aviso' } else { 'Texto' })))) {
        $tile = Tarjeta (Apilar @((Texto $x[0] 12 'Normal' 'Texto2'), (Texto $x[1] 24 'SemiBold' $x[2])))
        $tile.Margin = '0,0,8,0'; [void]$tiles.Children.Add($tile)
    }
    $tiles.Children[2].Margin = '0'
    [void]$panel.Children.Add($tiles)
    if (-not $plan.Discos) {
        $f = Fila @((Icono $GlifoDisco 22), (Texto "Todavía no hay discos de backup. Conecta uno externo y vuelve al paso anterior, o sigue y te avisaré cuando lo conectes." 13 'Normal' 'Texto2')) @('Auto', '*')
        $f.Children[1].Margin = '12,0,0,0'
        [void]$panel.Children.Add((Tarjeta $f))
    }
    foreach ($d in $plan.Discos) {
        $det = ($discosInfo | Where-Object { $_.Id -eq $d.Id } | Select-Object -First 1).Detalle
        $cab = Fila @((Icono $GlifoDisco 22 'Acento'), (Apilar @((Texto $d.Nombre 15 'SemiBold'), (Texto "$det" 11.5 'Normal' 'Texto2'))), (Chip "Copia $($d.Frecuencia)" 'acento')) @('Auto', '*', 'Auto')
        $cab.Children[1].Margin = '12,0,0,0'
        $uso = Apilar @((BarraUso ($d.Asignado / [math]::Max(1.0, [double]$d.Util))), (Texto "$(TamTxt $d.Asignado) de $(TamTxt $d.Util) útiles" 12 'Normal' 'Texto2'))
        $uso.Margin = '0,12,0,8'; $uso.Children[1].Margin = '0,6,0,0'
        $carps = New-Object Windows.Controls.StackPanel
        foreach ($c in $d.Carpetas) {
            $parte = if ($c.EnEspera -gt 0 -or @($c.Discos).Count -gt 1) { Chip "una parte" } else { $null }
            $fila = Fila @((Icono $GlifoCarpeta 14), (Texto (NombreCorto $c.Carpeta) 13), $parte, (Chip $TextoPrioridad[$c.Prioridad] $(if ($c.Prioridad -eq 1) { 'acento' } else { 'normal' }))) @('Auto', '*', 'Auto', 'Auto')
            $fila.Children[1].Margin = '10,0,0,0'; $fila.Children[1].ToolTip = $c.Carpeta; $fila.Margin = '0,3,0,3'
            [void]$carps.Children.Add($fila)
        }
        if (-not $d.Carpetas) { [void]$carps.Children.Add((Texto "Nada asignado todavía." 12 'Normal' 'Texto2')) }
        [void]$panel.Children.Add((Tarjeta (Apilar @($cab, $uso, $carps))))
    }
    $esp = @($plan.Carpetas | Where-Object { $_.EnEspera -gt 0 })
    if ($esp) {
        $l = New-Object Windows.Controls.StackPanel
        $cab = Fila @((Icono $GlifoAviso 20 'Aviso'), (Texto "No cabe todavía: $(TamTxt $plan.EnEspera)" 15 'SemiBold' 'Aviso')) @('Auto', '*')
        $cab.Children[1].Margin = '10,0,0,0'; [void]$l.Children.Add($cab)
        $x = Texto "Se copiará automáticamente en cuanto registres otro disco con sitio." 12 'Normal' 'Texto2'; $x.Margin = '0,4,0,8'; [void]$l.Children.Add($x)
        foreach ($c in $esp) {
            $f = Fila @((Texto (NombreCorto $c.Carpeta) 13), (Texto "$($c.EnEspera) de $($c.Unidades) subcarpetas $([char]0x00B7) $(TamTxt $c.BytesEspera)" 12 'Normal' 'Texto2')) @('*', 'Auto')
            $f.Margin = '0,3,0,3'; $f.Children[0].ToolTip = $c.Carpeta; [void]$l.Children.Add($f)
        }
        [void]$panel.Children.Add((Tarjeta $l 'AvisoSuave' 'AvisoSuave'))
    }
    $rec = if ($plan.Comprar) { Fila @((Icono $GlifoCompra 22 'Acento'), (Apilar @((Texto "Te conviene un disco externo de $(TamComercial $plan.Comprar)" 15 'SemiBold'), (Texto "Formatéalo en NTFS para que la copia vaya comprimida. Al conectarlo te ofreceré registrarlo." 12 'Normal' 'Texto2')))) @('Auto', '*') }
           else { Fila @((Icono $GlifoOk 22 'Acento'), (Texto "Tus discos tienen sitio suficiente por ahora." 14 'SemiBold')) @('Auto', '*') }
    $rec.Children[1].Margin = '12,0,0,0'
    [void]$panel.Children.Add((Tarjeta $rec 'AcentoSuave' 'AcentoSuave'))
    $notas = @()
    if ($plan.SinHistorial) { $notas += "Aún no hay historial de tamaños: se reserva un 20 % para el crecimiento de los próximos 2 años." }
    else { $notas += "Tus carpetas crecen unos $(TamTxt $plan.CrecimientoAnual) al año." }
    if ($ahorro -gt 1GB) { $notas += "No se copian carpetas que se regeneran solas ($(($Excluir | Select-Object -First 3) -join ', ')...): ahorras $(TamTxt $ahorro)." }
    foreach ($n in $notas) { $x = Texto $n 12 'Normal' 'Texto2'; $x.Margin = '4,4,0,0'; [void]$panel.Children.Add($x) }
}
function CalcularPlan {
    $a = $script:asis; $panel = $a.Win.FindName('ListaPlan')
    $m = @(MarcadasAsis)
    $med = @($m | ForEach-Object { MedidaDe $_ })
    $hechas = [int](($med | Measure-Object Medidas -Sum).Sum); $total = [int](($med | Measure-Object Total -Sum).Sum)
    if ($hechas -lt $total) {
        $panel.Children.Clear()
        $p = New-Object Windows.Controls.ProgressBar; $p.Height = 4; $p.IsIndeterminate = $true; $p.BorderThickness = 0; $p.Margin = '0,12,0,0'
        Recurso $p ([Windows.Controls.ProgressBar]::ForegroundProperty) 'Acento'; Recurso $p ([Windows.Controls.ProgressBar]::BackgroundProperty) 'Barra'
        [void]$panel.Children.Add((Tarjeta (Apilar @((Texto "Midiendo tus carpetas..." 15 'SemiBold'), (Texto "$hechas de $total subcarpetas. El plan aparecerá en cuanto termine." 12 'Normal' 'Texto2'), $p))))
        $a.Plan = $null; $a.Win.FindName('BtnSig').IsEnabled = $false; return
    }
    $a.Win.Cursor = [Windows.Input.Cursors]::Wait
    $carps = @($m | ForEach-Object { $_.Carpeta })
    $units = @($m | ForEach-Object { $_.Unidades })
    $discos = @(DiscosElegidos)
    $ids = @($discos | ForEach-Object { $_.Id })
    $rep = @{}; $viejo = LeerReparto
    foreach ($u in $units) { if ($viejo.ContainsKey($u.Clave) -and $ids -contains $viejo[$u.Clave]) { $rep[$u.Clave] = $viejo[$u.Clave] } }
    $rep = Repartir $units $a.Tam $discos $rep
    $plan = PlanDeCopias $discos $rep $a.Tam $carps
    $a.Plan = $plan; $a.Rep = $rep; $a.DiscosPlan = $discos
    $ahorro = [int64]0; foreach ($u in $units) { if ($a.Total.ContainsKey($u.Clave)) { $ahorro += $a.Total[$u.Clave] - $a.Tam[$u.Clave] } }
    PintarPlan $panel $plan $ahorro $discos
    $a.Win.Cursor = $null
    $a.Win.FindName('BtnSig').IsEnabled = $true
}
function GuardarPlanAsis {
    $a = $script:asis
    if (-not $a.Plan) { return $false }
    $m = @(MarcadasAsis)
    $nuevos = @($a.DiscosPlan | Where-Object { $_.Nuevo })
    $quitados = @(LeerDiscos | Where-Object { @($a.DiscosPlan | ForEach-Object { $_.Id }) -notcontains $_.Id })
    $msg = "Se guardará el plan con $($m.Count) carpetas."
    foreach ($d in $nuevos) { $msg += "`n`n$([char]0x2022) Se registrará el disco '$($d.NombreReal)' ($($d.Letra)): se crea en él la carpeta $CarpetaBackup con una marca oculta. No se borra nada del disco." }
    foreach ($d in $quitados) { $msg += "`n`n$([char]0x2022) Se dejará de usar el disco '$($d.Nombre)'. No se borra nada de él." }
    if (-not $a.SinPreguntar -and (Dialogo $a.Win "Guardar el plan" $msg @('Cancelar', 'Guardar plan') 'Guardar plan') -ne 'Guardar plan') { return $false }

    EscribirCarpetas @($m | ForEach-Object { $_.Carpeta })
    $diasDe = @{}; foreach ($d in $a.Plan.Discos) { $diasDe[$d.Id] = $d.Dias }
    # Discos que se siguen usando: nombre y frecuencia del plan
    $lista = @(LeerDiscos | Where-Object { @($a.DiscosPlan | ForEach-Object { $_.Id }) -contains $_.Id })
    foreach ($r in $lista) {
        $d = $a.DiscosPlan | Where-Object { $_.Id -eq $r.Id } | Select-Object -First 1
        $r.Nombre = $d.NombreReal
        $r | Add-Member -NotePropertyName Dias -NotePropertyValue $diasDe[$r.Id] -Force
    }
    GuardarDiscos $lista
    $mapa = @{}
    foreach ($d in $nuevos) {
        try { $mapa[$d.Id] = RegistrarDisco $d.Letra $d.NombreReal $diasDe[$d.Id] }
        catch { [void](Dialogo $a.Win "No se pudo registrar el disco" "$($d.Letra): $($_.Exception.Message)") }
    }
    $rep = @{}
    foreach ($k in @($a.Rep.Keys)) { $v = $a.Rep[$k]; if ($mapa.ContainsKey($v)) { $v = $mapa[$v] } elseif ($v -like 'nuevo:*') { $v = $EnEspera }; $rep[$k] = $v }
    GuardarReparto $rep
    # Los tamanos medidos se guardan para que el icono y la copia no tengan que volver a medir
    $tam = LeerTamUnidades; foreach ($k in @($a.Tam.Keys)) { $tam[$k] = $a.Tam[$k] }
    $hoy = Get-Date -Format 'yyyy-MM-dd'
    $tam.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Unidad = $_.Key; Bytes = $_.Value; Fecha = $hoy } } |
        Export-Csv $FicheroUnidades -Delimiter ';' -NoTypeInformation -Encoding UTF8
    return $true
}

# ---------- Ventana ----------
$XamlAsistente = @"
<Window $VentanaBase Title="BackupApp" Width="1080" Height="720" MinWidth="900" MinHeight="580" WindowStartupLocation="CenterScreen">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="250"/><ColumnDefinition/></Grid.ColumnDefinitions>
    <Border Background="{DynamicResource Lateral}" BorderBrush="{DynamicResource Borde}" BorderThickness="0,0,1,0">
      <DockPanel Margin="22,26,22,22">
        <StackPanel DockPanel.Dock="Top" Orientation="Horizontal">
          <Image x:Name="Logo" Width="40" Height="40"/>
          <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
            <TextBlock Text="BackupApp" FontSize="17" FontWeight="SemiBold"/>
            <TextBlock x:Name="TxtVersion" FontSize="11" Foreground="{DynamicResource Texto2}"/>
          </StackPanel>
        </StackPanel>
        <StackPanel DockPanel.Dock="Bottom">
          <TextBlock Text="Apariencia" FontSize="11" Foreground="{DynamicResource Texto2}" Margin="2,0,0,8"/>
          <StackPanel Orientation="Horizontal">
            <RadioButton x:Name="TemaSistema" Style="{DynamicResource Pastilla}" GroupName="Tema" Content="Sistema"/>
            <RadioButton x:Name="TemaClaro" Style="{DynamicResource Pastilla}" GroupName="Tema" Content="Claro"/>
            <RadioButton x:Name="TemaOscuro" Style="{DynamicResource Pastilla}" GroupName="Tema" Content="Oscuro"/>
          </StackPanel>
        </StackPanel>
        <StackPanel x:Name="Pasos" Margin="0,44,0,0"/>
      </DockPanel>
    </Border>
    <Grid Grid.Column="1" Margin="40,30,40,26">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <TextBlock x:Name="Titulo" FontSize="28" FontWeight="SemiBold" FontFamily="Segoe UI Variable Display, Segoe UI"/>
      <TextBlock x:Name="Desc" Grid.Row="1" Foreground="{DynamicResource Texto2}" TextWrapping="Wrap" Margin="0,6,0,20" FontSize="13.5"/>
      <Grid Grid.Row="2">
        <DockPanel x:Name="P0">
          <DockPanel DockPanel.Dock="Bottom" Margin="0,12,0,0">
            <Button x:Name="BtnAnadir" Content="+  Añadir otra carpeta" DockPanel.Dock="Left"/>
            <TextBlock x:Name="TxtTotal" HorizontalAlignment="Right" VerticalAlignment="Center" FontWeight="SemiBold"/>
          </DockPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0,0,10,0"><StackPanel x:Name="Lista"/></ScrollViewer>
        </DockPanel>
        <DockPanel x:Name="P1" Visibility="Collapsed">
          <DockPanel DockPanel.Dock="Bottom" Margin="0,12,0,0">
            <Button x:Name="BtnActualizar" Content="Actualizar" DockPanel.Dock="Left"/>
            <TextBlock Margin="16,0,0,0" VerticalAlignment="Center" TextWrapping="Wrap" Foreground="{DynamicResource Texto2}" FontSize="12" Text="¿Aún no has conectado tu disco externo? Conéctalo y pulsa Actualizar. También puedes seguir sin disco: el plan te dirá cuál comprar."/>
          </DockPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0,0,10,0"><StackPanel x:Name="ListaDiscos"/></ScrollViewer>
        </DockPanel>
        <ScrollViewer x:Name="P2" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0,0,10,0"><StackPanel x:Name="ListaPlan"/></ScrollViewer>
      </Grid>
      <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,20,0,0">
        <Button x:Name="BtnCancelar" Content="Cancelar" Margin="0,0,8,0"/>
        <Button x:Name="BtnAtras" Content="Atrás" Margin="0,0,8,0"/>
        <Button x:Name="BtnSig" Content="Siguiente" Style="{DynamicResource Primario}" MinWidth="120"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
"@
$PasosAsis = @(
    @{ Nombre = 'Carpetas'; Titulo = '¿Qué quieres proteger?'; Desc = 'Marca las carpetas que quieres copiar. Se miden mientras eliges. Si no caben todas, se copian antes las imprescindibles.' },
    @{ Nombre = 'Discos'; Titulo = '¿Dónde se guarda la copia?'; Desc = 'Estas son las unidades de tu PC. Marca los discos que quieres usar para el backup; mejor si son externos.' },
    @{ Nombre = 'Plan'; Titulo = 'Tu plan de copias'; Desc = 'Esto es lo que se copiará en cada disco y cada cuánto. Todavía no se ha guardado nada.' })
function PintarPasos {
    $a = $script:asis; $sp = $a.Win.FindName('Pasos'); $sp.Children.Clear()
    for ($i = 0; $i -lt $PasosAsis.Count; $i++) {
        $estado = if ($i -lt $a.Paso) { 'hecho' } elseif ($i -eq $a.Paso) { 'actual' } else { 'futuro' }
        $circ = New-Object Windows.Controls.Border; $circ.Width = 28; $circ.Height = 28; $circ.CornerRadius = 14
        $num = Texto $(if ($estado -eq 'hecho') { [string][char]0x2713 } else { "$($i + 1)" }) 13 'SemiBold' $(if ($estado -eq 'actual') { 'AcentoTexto' } elseif ($estado -eq 'hecho') { 'Acento' } else { 'Texto2' })
        $num.HorizontalAlignment = 'Center'; $num.VerticalAlignment = 'Center'; $circ.Child = $num
        Recurso $circ ([Windows.Controls.Border]::BackgroundProperty) $(if ($estado -eq 'actual') { 'Acento' } elseif ($estado -eq 'hecho') { 'AcentoSuave' } else { 'Borde' })
        $txt = Texto $PasosAsis[$i].Nombre 14 $(if ($estado -eq 'actual') { 'SemiBold' } else { 'Normal' }) $(if ($estado -eq 'futuro') { 'Texto2' } else { 'Texto' })
        $txt.Margin = '12,0,0,0'
        $f = Fila @($circ, $txt) @('Auto', '*'); $f.Margin = '0,0,0,14'
        [void]$sp.Children.Add($f)
    }
}
function IrAPaso($p) {
    $a = $script:asis; $w = $a.Win; $a.Paso = $p
    foreach ($i in 0..2) { $w.FindName("P$i").Visibility = $(if ($i -eq $p) { 'Visible' } else { 'Collapsed' }) }
    $w.FindName('Titulo').Text = $PasosAsis[$p].Titulo; $w.FindName('Desc').Text = $PasosAsis[$p].Desc
    $w.FindName('BtnAtras').Visibility = $(if ($p -gt 0) { 'Visible' } else { 'Collapsed' })
    $w.FindName('BtnSig').Content = $(if ($p -eq 2) { 'Finalizar' } else { 'Siguiente' })
    $w.FindName('BtnSig').IsEnabled = $true
    PintarPasos
    if ($p -eq 1) { $w.Cursor = [Windows.Input.Cursors]::Wait; LlenarDiscos; $w.Cursor = $null }
    if ($p -eq 2) { CalcularPlan }
}
function Siguiente {
    $a = $script:asis
    if ($a.Paso -eq 0) { $err = ValidarCarpetas; if ($err) { [void](Dialogo $a.Win "Revisa las carpetas" $err); return }; IrAPaso 1 }
    elseif ($a.Paso -eq 1) { IrAPaso 2 }
    elseif (GuardarPlanAsis) {
        $a.Guardado = $true
        $a.Win.Close()
        if ($a.AlTerminar) { & $a.AlTerminar }
    }
}
function MostrarAsistente($alTerminar = $null, [switch]$Modal) {
    if ($script:asis -and $script:asis.Win -and $script:asis.Win.IsVisible) { [void]$script:asis.Win.Activate(); return }
    $a = @{ Carpetas = [ordered]@{}; Tam = (LeerTamUnidades); Total = @{}; Decision = @{}; Paso = 0; Plan = $null; Guardado = $false
            Cola = (New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'); Trabajos = (New-Object 'System.Collections.Generic.List[object]')
            AlTerminar = $alTerminar; FilasDiscos = $null; SinPreguntar = $false; Iniciado = $false }
    $script:asis = $a
    $w = NuevaVentana $XamlAsistente
    $a.Win = $w; $a.Lista = $w.FindName('Lista')
    $w.FindName('Logo').Source = ImagenDe (RutaRecurso "logo.png")
    $w.FindName('TxtVersion').Text = "Versión $Version"
    $tema = LeerAjuste 'Tema' 'sistema'
    $w.FindName($(switch ($tema) { 'claro' { 'TemaClaro' } 'oscuro' { 'TemaOscuro' } default { 'TemaSistema' } })).IsChecked = $true
    foreach ($n in 'Sistema', 'Claro', 'Oscuro') {
        $rb = $w.FindName("Tema$n"); $rb.Tag = $n.ToLower()
        $rb.add_Checked({ param($s, $e) GuardarAjuste 'Tema' $s.Tag; AplicarTemaATodas })
    }
    $w.FindName('BtnAnadir').add_Click({ AnadirCarpetaAsis })
    $w.FindName('BtnActualizar').add_Click({ LlenarDiscos })
    $w.FindName('BtnAtras').add_Click({ IrAPaso ($script:asis.Paso - 1) })
    $w.FindName('BtnSig').add_Click({ Siguiente })
    $w.FindName('BtnCancelar').add_Click({ $script:asis.Win.Close() })

    # Resultados de la medicion en segundo plano
    $a.Timer = New-Object Windows.Threading.DispatcherTimer; $a.Timer.Interval = [TimeSpan]::FromMilliseconds(400)
    $a.Timer.add_Tick({
        $a = $script:asis; $r = $null; $hubo = $false
        while ($a.Cola.TryDequeue([ref]$r)) { $a.Tam[$r.Clave] = [int64]$r.BytesBackup; $a.Total[$r.Clave] = [int64]$r.Bytes; $hubo = $true }
        if ($hubo) { RefrescarTamanos; if ($a.Paso -eq 2 -and -not $a.Plan) { CalcularPlan } }
    })
    $w.add_Closed({
        $a = $script:asis; $a.Timer.Stop()
        foreach ($ps in $a.Trabajos) { try { $ps.Stop(); $ps.Dispose() } catch {} }
    })
    $w.add_ContentRendered({
        # Se rellena cuando la ventana ya se ve, para que no parezca colgada mientras busca carpetas
        $a = $script:asis
        if ($a.Iniciado) { return }; $a.Iniciado = $true
        $a.Win.Cursor = [Windows.Input.Cursors]::Wait; SugerirCarpetas; RefrescarTamanos; $a.Win.Cursor = $null
        $a.Timer.Start()
    })
    IrAPaso 0
    if ($Modal) { [void]$w.ShowDialog() } else { MostrarSinBloquear $w }
}

# Ejecutado suelto (no desde bandeja.ps1): abrir el asistente y esperar a que se cierre
if ($MyInvocation.InvocationName -ne '.') { MostrarAsistente -Modal }
