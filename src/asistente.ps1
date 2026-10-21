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
$GlifoAviso = [string][char]0xE7BA; $GlifoOk = [string][char]0xE73E; $GlifoCompra = [string][char]0xE7BF; $GlifoNube = [string][char]0xE753
$CuotasNube = @(2GB, 5GB, 15GB, 50GB, 100GB, 200GB, 1TB, 2TB)

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
    [void]$script:asis.Lista.Children.Add((TarjetaCarpeta $o))
    # Lo marcado se mide antes; lo demas, cuando el disco queda libre
    EncolarMedicion $o -Primero:$marcada
}
function TarjetaCarpeta($o) {
    $chk = New-Object Windows.Controls.CheckBox; $chk.IsChecked = $o.Marcada; $chk.Tag = $o.Ruta
    $chk.add_Click({ param($s, $e)
        $o = $script:asis.Carpetas[$s.Tag]; $o.Marcada = [bool]$s.IsChecked
        if ($o.Marcada) { EncolarMedicion $o -Primero }   # si estaba esperando, pasa delante
        RefrescarTamanos })
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
# ---------- Medicion en segundo plano ----------
# Un unico medidor recorre las carpetas de una en una (en un disco duro, medir varias a la vez es mas lento porque
# el cabezal salta de un sitio a otro). Hay dos colas: la prioritaria (lo marcado) y la normal (el resto).
# No entra en las carpetas que no se copian (node_modules...), que pueden tener cientos de miles de archivos.
function EncolarMedicion($o, [switch]$Primero) {
    $a = $script:asis
    foreach ($u in $o.Unidades) {
        if ($a.Tam.ContainsKey($u.Clave)) { continue }
        $antes = $a.Encolado[$u.Clave]
        if ($antes -eq 'alta' -or ($antes -eq 'baja' -and -not $Primero)) { continue }
        $a.Encolado[$u.Clave] = $(if ($Primero) { 'alta' } else { 'baja' })
        $item = [pscustomobject]@{ Clave = $u.Clave; Tipo = $u.Tipo; Origen = $u.Dir }
        if ($Primero) { $a.Alta.Enqueue($item) } else { $a.Baja.Enqueue($item) }
    }
    AsegurarMedidor
}
function AsegurarMedidor {
    $a = $script:asis
    if ($a.Medidor -and -not $a.Medidor.H.IsCompleted) { return }
    $a.Estado.Clave = $null   # si el medidor se paro a mitad, que no se quede marcada una carpeta como "midiendo"
    if ($a.Alta.IsEmpty -and $a.Baja.IsEmpty) { return }
    if ($a.Medidor) { try { $a.Medidor.PS.Dispose() } catch {} }
    $ps = [powershell]::Create()
    [void]$ps.AddScript({
        param($config, $alta, $baja, $res, $estado)
        . $config
        $u = $null
        $cont = $estado.Contador
        while ($alta.TryDequeue([ref]$u) -or $baja.TryDequeue([ref]$u)) {
            if ($estado.Hechas.ContainsKey($u.Clave)) { continue }   # ya medida (estaba en las dos colas)
            $cont[0] = 0; $estado.Clave = $u.Clave
            $err = $null
            try { $m = if ($u.Tipo -eq 'sueltos') { Analizar $u.Origen -SoloRaiz } else { Analizar $u.Clave -Rapido -Contador $cont } }
            catch { $m = [pscustomobject]@{ Bytes = 0; BytesBackup = 0 }; $err = "$($_.Exception.Message)" }   # se apunta y se sigue
            $estado.Hechas[$u.Clave] = $true
            $res.Enqueue([pscustomobject]@{ Clave = $u.Clave; Bytes = $m.Bytes; BytesBackup = $m.BytesBackup; Error = $err })
        }
        $estado.Clave = $null
    }.ToString())
    foreach ($x in @((Join-Path $Codigo "config.ps1"), $a.Alta, $a.Baja, $a.Cola, $a.Estado)) { [void]$ps.AddArgument($x) }
    $a.Medidor = @{ PS = $ps; H = $ps.BeginInvoke() }
}
function GuardarTamanosMedidos {
    $a = $script:asis
    $tam = LeerTamUnidades; foreach ($k in @($a.Tam.Keys)) { if (-not $a.Errores.ContainsKey($k)) { $tam[$k] = $a.Tam[$k] } }
    $hoy = Get-Date -Format 'yyyy-MM-dd'
    try { $tam.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Unidad = $_.Key; Bytes = $_.Value; Fecha = $hoy } } | Export-Csv $FicheroUnidades -Delimiter ';' -NoTypeInformation -Encoding UTF8 } catch {}
}
function MedidaDe($o) {
    # Lo medido de una carpeta, contando lo que lleva la subcarpeta que se esta midiendo ahora
    $a = $script:asis; $b = [int64]0; $n = 0; $parcial = [int64]0
    foreach ($u in $o.Unidades) {
        if ($a.Tam.ContainsKey($u.Clave)) { $b += $a.Tam[$u.Clave]; $n++ }
        elseif ($a.Estado.Clave -eq $u.Clave) { $parcial = [int64]$a.Estado.Contador[0] }
    }
    [pscustomobject]@{ Bytes = $b; Parcial = $parcial; Medidas = $n; Total = @($o.Unidades).Count; Completa = ($n -ge @($o.Unidades).Count) }
}
function RefrescarTamanos {
    $a = $script:asis; $total = [int64]0; $completo = $true; $n = 0
    foreach ($o in $a.Carpetas.Values) {
        $m = MedidaDe $o
        $o.TxtTam.Text = if ($m.Completa) { TamTxt $m.Bytes }
                         elseif ($m.Medidas -eq 0 -and $m.Parcial -eq 0) { if ($a.Encolado.Count -and ($o.Unidades | Where-Object { $a.Encolado[$_.Clave] -eq 'alta' })) { "en cola" } else { "pendiente" } }
                         else { "$(TamTxt ($m.Bytes + $m.Parcial))  $([char]0x00B7)  $($m.Medidas)/$($m.Total)" }
        if ($o.Marcada) { $n++; $total += $m.Bytes + $m.Parcial; if (-not $m.Completa) { $completo = $false } }
    }
    $a.Win.FindName('TxtTotal').Text = "$n carpetas $([char]0x00B7) $(TamTxt $total)$(if (-not $completo) { ' (midiendo...)' })"
}
function ProgresoMedicion {
    # Barra con porcentaje mientras se mide lo marcado (paso 3)
    $a = $script:asis; $panel = $a.Win.FindName('ListaPlan')
    $m = @(MarcadasAsis); $med = @($m | ForEach-Object { MedidaDe $_ })
    $hechas = [int](($med | Measure-Object Medidas -Sum).Sum); $total = [int](($med | Measure-Object Total -Sum).Sum)
    $bytes = [int64](($med | ForEach-Object { $_.Bytes + $_.Parcial } | Measure-Object -Sum).Sum)
    if (-not $a.ProgMed -or -not $panel.Children.Contains($a.ProgMed.Tarjeta)) {
        $panel.Children.Clear()
        $p = New-Object Windows.Controls.ProgressBar; $p.Height = 8; $p.Minimum = 0; $p.Maximum = 1; $p.BorderThickness = 0; $p.Margin = '0,14,0,8'
        Recurso $p ([Windows.Controls.ProgressBar]::ForegroundProperty) 'Acento'; Recurso $p ([Windows.Controls.ProgressBar]::BackgroundProperty) 'Barra'
        $pct = Texto "" 28 'SemiBold' 'Acento'; $det = Texto "" 12 'Normal' 'Texto2'; $ahora = Texto "" 12 'Normal' 'Texto2'
        $ahora.TextTrimming = 'CharacterEllipsis'; $ahora.TextWrapping = 'NoWrap'
        $cab = Fila @((Texto "Midiendo tus carpetas..." 15 'SemiBold'), $pct) @('*', 'Auto')
        $nota = Texto "El plan aparecerá en cuanto termine. Solo se mide lo que has marcado; la próxima vez será instantáneo porque se recuerdan los tamaños." 11.5 'Normal' 'Texto2'; $nota.Margin = '0,10,0,0'
        $card = Tarjeta (Apilar @($cab, $p, $det, $ahora, $nota))
        $a.ProgMed = @{ Tarjeta = $card; Barra = $p; Pct = $pct; Det = $det; Ahora = $ahora }
        [void]$panel.Children.Add($card)
    }
    $fr = if ($total) { $hechas / $total } else { 0 }
    $a.ProgMed.Barra.Value = $fr; $a.ProgMed.Pct.Text = "{0:N0} %" -f (100 * $fr)
    $a.ProgMed.Det.Text = "$hechas de $total subcarpetas  $([char]0x00B7)  $(TamTxt $bytes) contados"
    $actual = $a.Estado.Clave
    $a.ProgMed.Ahora.Text = if ($actual) { "Ahora: $actual" } else { "" }
}function MarcadasAsis { @($script:asis.Carpetas.Values | Where-Object { $_.Marcada }) }
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

# ---------- Paso 2: nube ----------
function LlenarNubes {
    $a = $script:asis; $lista = $a.Win.FindName('ListaNubes'); $lista.Children.Clear()
    $reg = @(LeerNubes)
    $a.FilasNubes = New-Object 'System.Collections.Generic.List[object]'
    # Las directas (rclone) registradas se muestran como una nube mas si su conexion sigue existiendo
    $directas = @($reg | Where-Object { $_.Tipo -eq 'rclone' -and (NubeDisponible $_) } | ForEach-Object { InfoNubeDirecta $_ })
    foreach ($d in @(@(DetectarNubes) + $directas + $a.NubesManuales.ToArray())) {   # (@() sobre una List vacia falla en PowerShell 5.1)
        if ($a.FilasNubes | Where-Object { $_.Info -and (ClaveNube $_.Info) -eq (ClaveNube $d) }) { continue }
        $r = $reg | Where-Object { ($d.IdMarca -and $_.Id -eq $d.IdMarca) -or (ClaveNube $_) -eq (ClaveNube $d) } | Select-Object -First 1
        $cuota = if ($d.Cuota) { [int64]$d.Cuota } elseif ($r) { [int64]$r.Capacidad } else { CuotaSugerida $d.Proveedor }
        if (-not $cuota) { $cuota = 5GB }
        $t = [pscustomobject]@{ Clave = $(if ($r) { $r.Id } else { ClaveNube $d }); Info = $d; Registro = $r; Nombre = $(if ($r) { $r.Nombre } else { $d.Nombre })
                               Marcar = $(if ($r) { $true } else { $d.Activa -eq $true }); Cuota = $cuota; CuotaFija = [bool]$d.Cuota
                               Prioridad = $(if ($r -and [int]$r.Prioridad -gt 0) { [int]$r.Prioridad } else { 1 }); Ajeno = $null }
        $a.FilasNubes.Add($t)
    }
    foreach ($r in $reg) {
        if ($a.FilasNubes | Where-Object { $_.Registro -and $_.Registro.Id -eq $r.Id }) { continue }
        $a.FilasNubes.Add([pscustomobject]@{ Clave = $r.Id; Info = $null; Registro = $r; Nombre = $r.Nombre; Marcar = $true; Cuota = [int64]$r.Capacidad; CuotaFija = $false; Prioridad = [int]$r.Prioridad; Ajeno = $r.Ajeno })
    }
    for ($k = 0; $k -lt $a.FilasNubes.Count; $k++) {
        $t = $a.FilasNubes[$k]
        if ($a.DecisionNube.ContainsKey($t.Clave)) { $dd = $a.DecisionNube[$t.Clave]; $t.Marcar = $dd.Marcar; $t.Cuota = $dd.Cuota; $t.Prioridad = $dd.Prioridad }
        [void]$lista.Children.Add((TarjetaNube $t $k))
    }
    $amazon = RutaAmazonPhotos
    if ($amazon) { [void]$lista.Children.Add((TarjetaAmazon $amazon)) }
    if (-not $a.FilasNubes.Count -and -not $amazon) {
        [void]$lista.Children.Add((Tarjeta (Texto "No hay ninguna nube instalada en este PC. Abajo tienes cómo conectar las más usadas." 13 'Normal' 'Texto2')))
    }
    PintarComoConectar
}
function ClaveNube($n) { if ($n.Tipo -eq 'rclone') { "rclone:$($n.Remoto)".ToLower() } else { "$($n.RaizSync)".ToLower() } }
function InfoNubeDirecta($r) {
    [pscustomobject]@{ Proveedor = $r.Proveedor; Nombre = $r.Nombre; RaizSync = ''; Cuota = $(if ($r.Proveedor -ne 'Backblaze B2') { [int64]$r.Capacidad }); Libre = $null
                       IdMarca = $null; Activa = $true; Tipo = 'rclone'; Remoto = $r.Remoto; RemotoBase = $r.RemotoBase; Cifrado = $r.Cifrado }
}
function GuardarDecisionNube($t) { $script:asis.DecisionNube[$t.Clave] = @{ Marcar = $t.Marcar; Cuota = $t.Cuota; Prioridad = $t.Prioridad } }
function TarjetaNube($t, $k) {
    $i = $t.Info
    $chk = New-Object Windows.Controls.CheckBox; $chk.IsChecked = $t.Marcar; $chk.Tag = $k; $chk.IsEnabled = [bool]$i -or [bool]$t.Registro
    $chk.add_Click({ param($s, $e) $t = $script:asis.FilasNubes[$s.Tag]; $t.Marcar = [bool]$s.IsChecked; GuardarDecisionNube $t })
    $ico = Icono $GlifoNube 26 'Acento'; $ico.Margin = '14,0,14,0'
    $prov = if ($i) { $i.Proveedor } else { $t.Registro.Proveedor }
    $directa = ($i -and $i.Tipo -eq 'rclone') -or $t.Registro.Tipo -eq 'rclone'
    $sub = if ($directa) { "$prov   $([char]0x00B7)   conexión directa, sin carpeta en el PC" } elseif ($i) { "$prov   $([char]0x00B7)   $($i.RaizSync)" } else { "$prov   $([char]0x00B7)   no se encuentra la carpeta $($t.Registro.RaizSync)" }
    $chips = New-Object Windows.Controls.WrapPanel; $chips.Margin = '0,6,0,0'
    if ($t.Registro) { [void]$chips.Children.Add((Chip "En uso" 'acento')) }
    if ($directa -and -not $i) { [void]$chips.Children.Add((Chip "Conexión no encontrada: vuelve a conectarla" 'aviso')) }
    elseif ($directa) { [void]$chips.Children.Add((Chip "Conexión directa" 'acento')); if ($i.Cifrado -eq 'si') { [void]$chips.Children.Add((Chip "Cifrada" 'acento')) } }
    elseif ($i -and $i.Activa -eq $true) { [void]$chips.Children.Add((Chip "$prov está abierto" 'acento')) }
    elseif ($i -and $i.Activa -eq $false) { [void]$chips.Children.Add((Chip "$prov no está abierto o no tiene sesión: no se subirá nada" 'aviso')) }
    elseif ($i) { [void]$chips.Children.Add((Chip "Carpeta sincronizada" 'normal')) }
    else { [void]$chips.Children.Add((Chip "Carpeta no encontrada" 'aviso')) }
    $det = Texto $sub 11.5 'Normal' 'Texto2'; $det.TextWrapping = 'NoWrap'; $det.TextTrimming = 'CharacterEllipsis'
    $info = Apilar @((Texto $t.Nombre 14 'SemiBold'), $det, $chips)
    $cab = Fila @($chk, $ico, $info) @('Auto', 'Auto', '*')
    # Opciones: espacio contratado y que subir
    $op = New-Object Windows.Controls.StackPanel; $op.Margin = '80,10,0,0'
    $fc = New-Object Windows.Controls.WrapPanel
    [void]$fc.Children.Add(($(Texto "Espacio contratado" 12 'Normal' 'Texto2') | ForEach-Object { $_.Width = 140; $_.VerticalAlignment = 'Center'; $_ }))
    if ($t.CuotaFija) { [void]$fc.Children.Add((Texto "$(TamTxt $t.Cuota) (lo indica $prov)" 12 'SemiBold')) }
    else {
        $cuotas = @($CuotasNube); if ($cuotas -notcontains $t.Cuota) { $cuotas = @($cuotas + $t.Cuota | Sort-Object) }
        foreach ($c in $cuotas) {
            $rb = New-Object Windows.Controls.RadioButton; $rb.Style = $script:Estilos['Pastilla']; $rb.Content = $(if ($c -ge 1TB) { "$($c / 1TB) TB" } else { "$($c / 1GB) GB" })
            $rb.GroupName = "cuota_$k"; $rb.IsChecked = ($c -eq $t.Cuota); $rb.Tag = "$k|$c"
            $rb.add_Checked({ param($s, $e) $k, $c = $s.Tag.Split('|'); $t = $script:asis.FilasNubes[[int]$k]; $t.Cuota = [int64]$c; GuardarDecisionNube $t })
            [void]$fc.Children.Add($rb)
        }
    }
    $fp = New-Object Windows.Controls.WrapPanel; $fp.Margin = '0,6,0,0'
    [void]$fp.Children.Add(($(Texto "Qué subir" 12 'Normal' 'Texto2') | ForEach-Object { $_.Width = 140; $_.VerticalAlignment = 'Center'; $_ }))
    foreach ($p in @(@(1, 'Solo lo imprescindible'), @(2, 'Imprescindible y normal'))) {
        $rb = New-Object Windows.Controls.RadioButton; $rb.Style = $script:Estilos['Pastilla']; $rb.Content = $p[1]
        $rb.GroupName = "prio_$k"; $rb.IsChecked = ($t.Prioridad -eq $p[0]); $rb.Tag = "$k|$($p[0])"
        $rb.add_Checked({ param($s, $e) $k, $p = $s.Tag.Split('|'); $t = $script:asis.FilasNubes[[int]$k]; $t.Prioridad = [int]$p; GuardarDecisionNube $t })
        [void]$fp.Children.Add($rb)
    }
    $op.Children.Add($fc) | Out-Null; $op.Children.Add($fp) | Out-Null
    $card = Tarjeta (Apilar @($cab, $op))
    if (-not $i) { $card.Opacity = 0.7 }
    return $card
}
function TarjetaAmazon($exe) {
    # Copia directa: BackupApp no copia nada; solo explica como decirle a Amazon Photos que suba las fotos
    $fotos = @(MarcadasAsis | Where-Object { $_.Ruta -match '(?i)foto|photo|imagen|picture|lightroom' } | ForEach-Object { $_.Ruta })
    $donde = if ($fotos) { "tus carpetas de fotos ($($fotos -join ', '))" } else { "tu carpeta de fotos" }
    $b = New-Object Windows.Controls.Button; $b.Content = "Abrir Amazon Photos"; $b.Tag = $exe
    $b.add_Click({ param($s, $e) Start-Process $s.Tag })
    $txt = Apilar @((Texto "Amazon Photos" 14 'SemiBold'), (Texto "Copia directa de fotos: su programa sube él mismo las carpetas que le indiques. Con Prime, fotos sin límite a resolución completa, también RAW (ARW, CR2, NEF...); los vídeos, 5 GB." 12 'Normal' 'Texto2'), (Texto "Para usarlo: abre Amazon Photos > Copia de seguridad > Añadir carpeta y elige $donde. No hace falta marcar nada aquí." 12 'SemiBold'))
    $txt.Children[1].Margin = '0,2,0,6'
    $ico = Icono $GlifoNube 26 'Acento'; $ico.Margin = '36,0,14,0'
    $f = Fila @($ico, $txt, $b) @('Auto', '*', 'Auto'); $f.Children[1].Margin = '0,0,16,0'
    return (Tarjeta $f)
}
function PintarComoConectar {
    # Servicios que se pueden conectar directamente, sin instalar nada (rclone se descarga solo la primera vez)
    $p = $script:asis.Win.FindName('ComoConectar'); $p.Children.Clear()
    $hay = @($script:asis.FilasNubes | Where-Object { $_.Info -and $_.Info.Tipo -eq 'rclone' } | ForEach-Object { $_.Info.Proveedor })
    [void]$p.Children.Add((Texto "Conectar otra nube (opcional)" 14 'SemiBold'))
    $x = Texto "No hace falta instalar nada: pulsa Conectar, inicia sesión y listo. La copia va directa a tu cuenta y, si quieres, cifrada con tu contraseña." 12 'Normal' 'Texto2'
    $x.Margin = '0,2,0,10'; [void]$p.Children.Add($x)
    $g = New-Object Windows.Controls.Primitives.UniformGrid; $g.Columns = 2
    foreach ($s in $ServiciosRclone) {
        $gratis = ($ServiciosNube | Where-Object { $_.Proveedor -eq $s.Nombre } | Select-Object -First 1).Gratis
        $nota = if ($hay -contains $s.Nombre) { "Ya conectado" } elseif ($s.Tipo -eq 'b2') { "Pagas solo lo que usas" } elseif ($s.Tipo -eq 'protondrive') { "Cifrado de extremo a extremo" } elseif ($gratis) { "$(TamTxt $gratis) gratis" } else { "" }
        $b = New-Object Windows.Controls.Button; $b.Style = $script:Estilos['Enlace']; $b.Content = "Conectar"; $b.Tag = $s.Tipo
        $b.add_Click({ param($x, $e) MostrarConectarDirecta $x.Tag })
        $f = Fila @((Icono $GlifoNube 16 'Acento'), (Apilar @((Texto $s.Nombre 13 'SemiBold'), (Texto $nota 11.5 'Normal' 'Texto2'))), $b) @('Auto', '*', 'Auto')
        $f.Children[1].Margin = '10,0,10,0'
        $c = Tarjeta $f; $c.Margin = '0,0,8,8'; $c.Padding = '14,8'
        [void]$g.Children.Add($c)
    }
    [void]$p.Children.Add($g)
    # Los que no dejan conectarse desde otros programas
    $b = New-Object Windows.Controls.Button; $b.Style = $script:Estilos['Enlace']; $b.Content = "Qué es Amazon Photos"; $b.Tag = $AmazonPhotos.Url
    $b.add_Click({ param($x, $e)
        $r = Dialogo $script:asis.Win "Amazon Photos (opcional)" ("No hace falta para BackupApp. Si tienes Prime, guarda tus fotos sin límite y a resolución completa, también en RAW (ARW, CR2, NEF...); los vídeos, hasta 5 GB.`n`n" +
             "Amazon no permite que otros programas suban a Amazon Photos, así que BackupApp no puede conectarse directamente. Si lo quieres, usa su programa de escritorio (desde la web de Amazon Photos, con tu cuenta de Amazon): Copia de seguridad > Añadir carpeta y elige tu carpeta de fotos.") @('Cerrar', 'Abrir Amazon Photos') 'Abrir Amazon Photos'
        if ($r -eq 'Abrir Amazon Photos') { Start-Process $x.Tag }
    })
    $n = Fila @((Texto "iCloud y Amazon Photos no permiten conectarse desde otros programas: si los usas, necesitan su propio programa (BackupApp encontrará la carpeta de iCloud si lo tienes instalado)." 11.5 'Normal' 'Texto2'), $b) @('*', 'Auto')
    $n.Children[1].Margin = '12,0,0,0'; $n.Margin = '2,4,0,0'
    [void]$p.Children.Add($n)
}$XamlDirecta = @"
<Window $VentanaBase Title="Conectar una nube" Width="620" SizeToContent="Height" ResizeMode="NoResize" WindowStartupLocation="CenterOwner" ShowInTaskbar="False">
  <StackPanel Margin="28,24,28,22">
    <TextBlock Text="Conectar una cuenta directamente" FontSize="22" FontWeight="SemiBold"/>
    <TextBlock Foreground="{DynamicResource Texto2}" TextWrapping="Wrap" Margin="0,6,0,16" Text="BackupApp sube la copia directamente a tu cuenta: no tienes que instalar nada ni ocupa espacio en tu PC. (La primera vez prepara rclone, un componente gratuito y de código abierto: tarda un momento.)"/>
    <TextBlock Text="Servicio" FontSize="12" Foreground="{DynamicResource Texto2}" Margin="2,0,0,6"/>
    <WrapPanel x:Name="Servicios"/>
    <StackPanel x:Name="Claves" Margin="0,12,0,0"/>
    <CheckBox x:Name="Cifrar" IsChecked="True" Margin="0,18,0,0" Content="Cifrar los archivos antes de subirlos (recomendado)"/>
    <StackPanel x:Name="PanelClave" Margin="30,10,0,0">
      <TextBlock Text="Contraseña para el cifrado" FontSize="12" Foreground="{DynamicResource Texto2}" Margin="0,0,0,4"/>
      <PasswordBox x:Name="Clave1"/>
      <TextBlock Text="Repítela" FontSize="12" Foreground="{DynamicResource Texto2}" Margin="0,8,0,4"/>
      <PasswordBox x:Name="Clave2"/>
      <TextBlock TextWrapping="Wrap" Margin="0,8,0,0" FontSize="12" Foreground="{DynamicResource Aviso}" Text="Apúntala en un sitio seguro: sin ella nadie puede recuperar los archivos de la nube, ni siquiera BackupApp."/>
    </StackPanel>
    <TextBlock x:Name="Estado" TextWrapping="Wrap" Margin="0,18,0,0" FontWeight="SemiBold"/>
    <ProgressBar x:Name="Barra" Height="4" Margin="0,8,0,0" IsIndeterminate="True" BorderThickness="0" Foreground="{DynamicResource Acento}" Background="{DynamicResource Barra}" Visibility="Collapsed"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,20,0,0">
      <Button x:Name="BtnCancelar" Content="Cancelar" Margin="0,0,8,0"/>
      <Button x:Name="BtnConectar" Content="Conectar" Style="{DynamicResource Primario}" MinWidth="120"/>
    </StackPanel>
  </StackPanel>
</Window>
"@
function MostrarConectarDirecta($tipo = 'drive') {
    $w = NuevaVentana $XamlDirecta; $w.Owner = $script:asis.Win
    $script:dir = @{ Win = $w; Servicio = ($ServiciosRclone | Where-Object { $_.Tipo -eq $tipo } | Select-Object -First 1); Cajas = @{}; Paso = $null; Ps = $null; H = $null; Proc = $null; Nombre = $null; Timer = $null }
    foreach ($s in $ServiciosRclone) {
        $rb = New-Object Windows.Controls.RadioButton; $rb.Style = $script:Estilos['Pastilla']; $rb.Content = $s.Nombre; $rb.GroupName = 'srv'; $rb.Tag = $s.Tipo
        $rb.IsChecked = ($s.Tipo -eq $tipo); $rb.Margin = '0,0,4,6'
        $rb.add_Checked({ param($x, $e) $script:dir.Servicio = $ServiciosRclone | Where-Object { $_.Tipo -eq $x.Tag }; PintarClavesDirecta })
        [void]$w.FindName('Servicios').Children.Add($rb)
    }
    $w.FindName('Cifrar').add_Click({ param($x, $e) $script:dir.Win.FindName('PanelClave').Visibility = $(if ($x.IsChecked) { 'Visible' } else { 'Collapsed' }) })
    $w.FindName('BtnCancelar').add_Click({ $script:dir.Win.Close() })
    $w.FindName('BtnConectar').add_Click({ EmpezarConexionDirecta })
    $w.add_Closed({ $d = $script:dir; if ($d.Timer) { $d.Timer.Stop() }; if ($d.Proc -and -not $d.Proc.Proceso.HasExited) { try { $d.Proc.Proceso.Kill() } catch {} } })
    PintarClavesDirecta
    [void]$w.ShowDialog()
}
function PintarClavesDirecta {
    # Servicios que no usan el navegador (Backblaze B2) piden sus claves
    $d = $script:dir; $p = $d.Win.FindName('Claves'); $p.Children.Clear(); $d.Cajas = @{}
    if (-not $d.Servicio.Claves) { $x = Texto "Al pulsar Conectar se abrirá el navegador para que inicies sesión en $($d.Servicio.Nombre) y des permiso a BackupApp." 12 'Normal' 'Texto2'; [void]$p.Children.Add($x); return }
    $x = Texto "Tus datos de acceso se guardan solo en este PC, ofuscados." 12 'Normal' 'Texto2'; [void]$p.Children.Add($x)
    foreach ($c in $d.Servicio.Claves) {
        $l = Texto $c[1] 12 'Normal' 'Texto2'; $l.Margin = '0,8,0,4'; [void]$p.Children.Add($l)
        $tb = if ($c[2]) { New-Object Windows.Controls.PasswordBox } else { New-Object Windows.Controls.TextBox }
        $tb.Tag = [bool]$c[3]   # opcional
        [void]$p.Children.Add($tb); $d.Cajas[$c[0]] = $tb
    }
}
function ValorCaja($c) { if ($c -is [Windows.Controls.PasswordBox]) { $c.Password } else { $c.Text.Trim() } }
function EstadoDirecta($txt, $ocupado = $true) {
    $w = $script:dir.Win; $w.FindName('Estado').Text = $txt
    $w.FindName('Barra').Visibility = $(if ($ocupado) { 'Visible' } else { 'Collapsed' })
    $w.FindName('BtnConectar').IsEnabled = -not $ocupado
}
function EmpezarConexionDirecta {
    $d = $script:dir; $w = $d.Win
    if ($w.FindName('Cifrar').IsChecked) {
        $c1 = $w.FindName('Clave1').Password; $c2 = $w.FindName('Clave2').Password
        if ($c1.Length -lt 8) { EstadoDirecta "La contraseña debe tener al menos 8 caracteres." $false; return }
        if ($c1 -ne $c2) { EstadoDirecta "Las dos contraseñas no coinciden." $false; return }
    }
    foreach ($k in $d.Cajas.Keys) { if (-not $d.Cajas[$k].Tag -and -not (ValorCaja $d.Cajas[$k])) { EstadoDirecta "Rellena los datos de $($d.Servicio.Nombre)." $false; return } }
    $d.Timer = New-Object Windows.Threading.DispatcherTimer; $d.Timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $d.Timer.add_Tick({ SeguirConexionDirecta })
    if (RcloneInstalado) { $d.Paso = 'login' }
    else {
        # La descarga va en otro hilo para que la ventana no se congele
        EstadoDirecta "Descargando rclone desde rclone.org y comprobando que es el original..."
        $ps = [powershell]::Create(); [void]$ps.AddScript({ param($c) . $c; InstalarRclone }.ToString()).AddArgument((Join-Path $Codigo "config.ps1"))
        $d.Ps = $ps; $d.H = $ps.BeginInvoke(); $d.Paso = 'instalar'
    }
    $d.Timer.Start()
}
function SeguirConexionDirecta {
    $d = $script:dir; $w = $d.Win
    switch ($d.Paso) {
        'instalar' {
            if (-not $d.H.IsCompleted) { return }
            $err = @($d.Ps.EndInvoke($d.H)) | Select-Object -First 1; $d.Ps.Dispose()
            if ($err) { $d.Timer.Stop(); EstadoDirecta $err $false; return }
            $d.Paso = 'login'
        }
        'login' {
            $d.Nombre = NuevoNombreRemoto
            $claves = @{}; foreach ($k in $d.Cajas.Keys) { $claves[$k] = ValorCaja $d.Cajas[$k] }
            $d.Proc = ConectarCuentaRclone $d.Servicio $d.Nombre $claves
            EstadoDirecta $(if ($d.Servicio.Claves) { "Comprobando las claves de $($d.Servicio.Nombre)..." } else { "Se ha abierto el navegador: inicia sesión en $($d.Servicio.Nombre) y acepta el permiso. Después vuelve aquí." })
            $d.Paso = 'esperando'
        }
        'esperando' {
            if (-not $d.Proc.Proceso.HasExited) { return }
            $d.Timer.Stop()
            if ($d.Proc.Proceso.ExitCode -ne 0 -or -not (RemotoExiste $d.Nombre)) {
                $e = ("$($d.Proc.Error.Result)" -split "`r?`n" | Where-Object { $_ -match 'ERROR|Failed|error' } | Select-Object -Last 1)
                [void](Rclone @('config', 'delete', $d.Nombre))
                EstadoDirecta "No se pudo conectar con $($d.Servicio.Nombre). $e" $false; return
            }
            $cifrar = [bool]$w.FindName('Cifrar').IsChecked
            EstadoDirecta "Conectado. Preparando la copia$(if ($cifrar) { ' cifrada' })..."
            if ($cifrar -and -not (CrearCifrado $d.Nombre $w.FindName('Clave1').Password)) { EstadoDirecta "No se pudo preparar el cifrado." $false; return }
            $q = CuotaRclone "$($d.Nombre):"
            $info = [pscustomobject]@{ Proveedor = $d.Servicio.Nombre; Nombre = "$($d.Servicio.Nombre) (directo)"; RaizSync = ''; Cuota = $(if ($q) { $q.Total }); Libre = $(if ($q) { $q.Libre })
                                       IdMarca = $null; Activa = $true; Tipo = 'rclone'; Remoto = $(if ($cifrar) { "$($d.Nombre)_c:" } else { "$($d.Nombre):BackupApp" })
                                       RemotoBase = "$($d.Nombre):"; Cifrado = $(if ($cifrar) { 'si' } else { 'no' }) }
            $script:asis.NubesManuales.Add($info)
            $script:asis.DecisionNube[(ClaveNube $info)] = @{ Marcar = $true; Cuota = $(if ($q) { $q.Total } else { 100GB }); Prioridad = 1 }
            $w.Close()
            LlenarNubes
        }
    }
}
function AnadirNubeManual {
    $r = ElegirCarpeta $script:asis.Win "Elige la carpeta que sincroniza tu nube o tu NAS"
    if (-not $r) { return }
    if ($r.TrimEnd('\') -match '^[A-Za-z]:$') { [void](Dialogo $script:asis.Win "Elige una carpeta" "Elige la carpeta que sincroniza tu servicio, no una unidad entera."); return }
    foreach ($x in MarcadasAsis) { if ((DentroDe $r $x.Ruta) -or (DentroDe $x.Ruta $r)) { [void](Dialogo $script:asis.Win "Esa carpeta no sirve" "Está dentro de una carpeta que vas a copiar (o la contiene): se copiaría dentro de sí misma."); return } }
    $script:asis.NubesManuales.Add((NubeElegida $r))
    $script:asis.DecisionNube[$r.TrimEnd('\').ToLower()] = @{ Marcar = $true; Cuota = 5GB; Prioridad = 1 }
    LlenarNubes
}
function NubesElegidas {
    foreach ($t in @($script:asis.FilasNubes | Where-Object { $_.Marcar })) {
        $i = $t.Info
        if (-not $i) {   # registrada pero ahora no se encuentra: se conserva tal cual
            $r = $t.Registro
            [pscustomobject]@{ Id = $r.Id; Nombre = $r.Nombre; Proveedor = $r.Proveedor; RaizSync = $r.RaizSync; Capacidad = [int64]$t.Cuota; Prioridad = $t.Prioridad
                               UltimaCopia = $r.UltimaCopia; Dias = $(if ($r.Dias) { $r.Dias } else { 7 }); Ajeno = [int64]$r.Ajeno; Nueva = $false; Activa = $null
                               Tipo = $r.Tipo; Remoto = $r.Remoto; RemotoBase = $r.RemotoBase; Cifrado = $r.Cifrado }
            continue
        }
        if ($null -eq $t.Ajeno) {
            $t.Ajeno = if ($i.Tipo -eq 'rclone') { if ($t.Registro) { [int64]$t.Registro.Ajeno } elseif ($i.Cuota -and $null -ne $i.Libre) { [int64]$i.Cuota - [int64]$i.Libre } else { 0 } }
                       else { AjenoNube $i.RaizSync $i.Cuota $i.Libre }
        }
        [pscustomobject]@{ Id = $(if ($t.Registro) { $t.Registro.Id } elseif ($i.IdMarca) { $i.IdMarca } else { "nube:$($i.RaizSync)" }); Nombre = $t.Nombre; Proveedor = $i.Proveedor
                           RaizSync = $i.RaizSync; Capacidad = [int64]$t.Cuota; Prioridad = $t.Prioridad; UltimaCopia = $(if ($t.Registro) { $t.Registro.UltimaCopia } else { '' })
                           Dias = 7; Ajeno = [int64]$t.Ajeno; Nueva = -not $t.Registro; Activa = $i.Activa
                           Tipo = $(if ($i.Tipo) { $i.Tipo } else { 'carpeta' }); Remoto = $i.Remoto; RemotoBase = $i.RemotoBase; Cifrado = $i.Cifrado }
    }
}

# ---------- Paso 3: plan ----------
function TarjetaPlanNube($np) {
    $n = $np.Nube; $p = $np.P
    $cab = Fila @((Icono $GlifoNube 22 'Acento'), (Apilar @((Texto $n.Nombre 15 'SemiBold'), (Texto $(if ($n.Tipo -eq 'rclone') { "Copia extra en la nube $([char]0x00B7) se sube directamente$(if ($n.Cifrado -eq 'si') { ', cifrada' })" } else { "Copia extra en la nube $([char]0x00B7) se sube con $($n.Proveedor)" }) 11.5 'Normal' 'Texto2'))), (Chip "Cada semana, sola" 'acento')) @('Auto', '*', 'Auto')
    $cab.Children[1].Margin = '12,0,0,0'
    $uso = Apilar @((BarraUso ($p.Bytes / [math]::Max(1.0, [double]$p.Util))), (Texto "$(TamTxt $p.Bytes) de $(TamTxt $p.Util) disponibles en tu espacio de $(TamTxt $n.Capacidad)" 12 'Normal' 'Texto2'))
    $uso.Margin = '0,12,0,8'; $uso.Children[1].Margin = '0,6,0,0'
    $l = New-Object Windows.Controls.StackPanel
    $todas = @(@($p.Seleccion) + @($p.Fuera))
    foreach ($g in ($p.Seleccion | Group-Object { $_.Carpeta.Origen })) {
        $tot = @($todas | Where-Object { $_.Carpeta.Origen -eq $g.Name }).Count
        $parte = if ($g.Count -lt $tot) { Chip "una parte" } else { $null }
        $f = Fila @((Icono $GlifoCarpeta 14), (Texto (NombreCorto $g.Name) 13), $parte) @('Auto', '*', 'Auto'); $f.Children[1].Margin = '10,0,0,0'; $f.Margin = '0,3,0,3'
        [void]$l.Children.Add($f)
    }
    if (-not $p.Seleccion) {
        $txt = if ($p.Fuera -and $p.Util -le 0) { "No queda espacio libre en esta nube." }
               elseif ($p.Fuera) { "Lo que toca subir no cabe en el espacio libre." }
               elseif ($p.YaEnNube) { "Todo lo que toca subir ya está en $($n.Proveedor). Si añades más carpetas imprescindibles, se subirán aquí." }
               else { "No hay carpetas que subir con esta prioridad." }
        [void]$l.Children.Add((Texto $txt 12 'Normal' 'Texto2'))
    }
    $ya = @($p.YaEnNube | ForEach-Object { NombreCorto $_.Carpeta.Origen } | Select-Object -Unique)
    if ($ya) { $x = Texto "Ya están en $($n.Proveedor), no hace falta subirlas: $($ya -join ', ')." 12 'Normal' 'Texto2'; $x.Margin = '0,8,0,0'; [void]$l.Children.Add($x) }
    if ($p.BytesFuera -gt 0) { $x = Texto "No caben $(TamTxt $p.BytesFuera). Puedes ampliar el espacio contratado o subir solo lo imprescindible." 12 'Normal' 'Aviso'; $x.Margin = '0,6,0,0'; [void]$l.Children.Add($x) }
    if ($n.Activa -eq $false) { $x = Texto "$($n.Proveedor) no está abierto: se copiará en su carpeta, pero no se subirá hasta que lo abras e inicies sesión." 12 'SemiBold' 'Aviso'; $x.Margin = '0,6,0,0'; [void]$l.Children.Add($x) }
    return (Tarjeta (Apilar @($cab, $uso, $l)))
}
function GrupoUnidad($u) {
    # Para resumir: la carpeta incluida y, si la unidad esta dentro de una carpeta abierta, esa carpeta
    $p = Split-Path $u.Rel -Parent
    "$(Split-Path $u.Carpeta.Origen -Leaf)$(if ($p) { " $([char]0x203A) $($p -replace '\\', " $([char]0x203A) ")" })"
}
function TarjetaCompras($compras) {
    # Plan de compras: un disco de 1 o 2 TB cada vez, con lo que se protegera en cada uno (lo imprescindible primero)
    $l = New-Object Windows.Controls.StackPanel
    $n = @($compras.Discos).Count
    $tit = if ($n) { "Plan de compras: $n $(if ($n -eq 1) { 'disco' } else { 'discos' }) de $(TamComercial $compras.Tamano)" } else { "Los discos de $(TamComercial $compras.Tamano) se quedan pequeños" }
    $cab = Fila @((Icono $GlifoCompra 22 'Acento'), (Apilar @((Texto $tit 15 'SemiBold'), (Texto "Ve comprándolos cuando quieras: cada uno que conectes se llena con lo siguiente de la lista, empezando por lo imprescindible. Las carpetas que no caben en un disco se dividen solas por sus subcarpetas." 12 'Normal' 'Texto2')))) @('Auto', '*')
    $cab.Children[1].Margin = '12,0,0,0'; [void]$l.Children.Add($cab)
    foreach ($d in $compras.Discos) {
        $grupos = @($d.Unidades | Group-Object { GrupoUnidad $_ } | ForEach-Object {
            [pscustomobject]@{ Nombre = $_.Name; N = $_.Count; Bytes = [int64](($_.Group | ForEach-Object { [int64]$compras.Tam[$_.Clave] } | Measure-Object -Sum).Sum); Pri = ($_.Group[0].Carpeta.Prioridad) } } |
            Sort-Object Pri, { -$_.Bytes })
        $bloque = New-Object Windows.Controls.StackPanel; $bloque.Margin = '34,12,0,0'
        $f = Fila @((Texto "Disco nuevo $($d.N)" 13.5 'SemiBold'), (Texto "$(TamTxt $d.Bytes) de $(TamTxt $d.Util)" 12 'Normal' 'Texto2')) @('*', 'Auto')
        [void]$bloque.Children.Add($f)
        $bu = BarraUso ($d.Bytes / [math]::Max(1.0, [double]$d.Util)); $bu.Margin = '0,6,0,6'; [void]$bloque.Children.Add($bu)
        foreach ($g in @($grupos | Select-Object -First 6)) {
            $noms = @($d.Unidades | Where-Object { (GrupoUnidad $_) -eq $g.Nombre } | ForEach-Object { $_.Nombre })
            $txt = "$($g.Nombre) $([char]0x203A) " + (($noms | Select-Object -First 4) -join ', ') + $(if ($noms.Count -gt 4) { " y $($noms.Count - 4) más" })
            $tx = Texto $txt 12.5; $tx.TextWrapping = 'Wrap'; $r = Fila @($tx, (Texto (TamTxt $g.Bytes) 12 'Normal' 'Texto2')) @('*', 'Auto'); $r.Margin = '0,2,0,2'; $r.Children[1].Margin = '12,0,0,0'
            [void]$bloque.Children.Add($r)
        }
        if ($grupos.Count -gt 6) { [void]$bloque.Children.Add((Texto "y $($grupos.Count - 6) grupos más" 12 'Normal' 'Texto2')) }
        [void]$l.Children.Add($bloque)
    }
    if ($compras.NoCaben) {
        $x = Texto "No caben ni en un disco vacío de $(TamComercial $compras.Tamano) ($(TamTxt $compras.BytesNoCaben)), porque no tienen subcarpetas para dividirlas: $((@($compras.NoCaben) | ForEach-Object { $_.Nombre } | Select-Object -First 4) -join ', '). Necesitarán un disco más grande." 12 'Normal' 'Aviso'
        $x.Margin = '34,12,0,0'; [void]$l.Children.Add($x)
    }
    return (Tarjeta $l 'AcentoSuave' 'AcentoSuave')
}
function PintarPlan($panel, $plan, $ahorro = 0, $discosInfo = $null, $nubesPlan = @()) {
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
    foreach ($np in $nubesPlan) { [void]$panel.Children.Add((TarjetaPlanNube $np)) }
    if ($plan.Compras -and ($plan.Compras.Discos -or $plan.Compras.NoCaben)) { [void]$panel.Children.Add((TarjetaCompras $plan.Compras)) }
    $rec = if ($plan.Compras -and $plan.Compras.Discos) { $null }
           elseif ($plan.Comprar) { Fila @((Icono $GlifoCompra 22 'Acento'), (Apilar @((Texto "Te conviene un disco externo de $(TamComercial $plan.Comprar)" 15 'SemiBold'), (Texto "Mejor en NTFS (como vienen casi todos). Al conectarlo te ofreceré registrarlo." 12 'Normal' 'Texto2')))) @('Auto', '*') }
           else { Fila @((Icono $GlifoOk 22 'Acento'), (Texto "Tus discos tienen sitio suficiente por ahora." 14 'SemiBold')) @('Auto', '*') }
    if ($rec) {
        $rec.Children[1].Margin = '12,0,0,0'
        [void]$panel.Children.Add((Tarjeta $rec 'AcentoSuave' 'AcentoSuave'))
    }
    $notas = @()
    if ($plan.SinHistorial) { $notas += "Aún no hay historial de tamaños: se reserva un 20 % para el crecimiento de los próximos 2 años." }
    else { $notas += "Tus carpetas crecen unos $(TamTxt $plan.CrecimientoAnual) al año." }
    if ($ahorro -gt 1GB) { $notas += "No se copian carpetas que se regeneran solas ($(($Excluir | Select-Object -First 3) -join ', ')...): ahorras $(TamTxt $ahorro)." }
    else { $notas += "No se copian las carpetas que se regeneran solas ($(($Excluir | Select-Object -First 3) -join ', ')...)." }
    if ($script:asis -and $script:asis.Errores.Count) { $notas += "No se pudieron medir $($script:asis.Errores.Count) subcarpetas (sin permiso o en uso): $((@($script:asis.Errores.Keys) | Select-Object -First 3) -join ', ')$(if ($script:asis.Errores.Count -gt 3) { '...' }). Se copiarán igualmente." }
    foreach ($n in $notas) { $x = Texto $n 12 'Normal' 'Texto2'; $x.Margin = '4,4,0,0'; [void]$panel.Children.Add($x) }
}
function CalcularPlan {
    $a = $script:asis; $panel = $a.Win.FindName('ListaPlan')
    $m = @(MarcadasAsis)
    $med = @($m | ForEach-Object { MedidaDe $_ })
    $hechas = [int](($med | Measure-Object Medidas -Sum).Sum); $total = [int](($med | Measure-Object Total -Sum).Sum)
    if ($hechas -lt $total) {
        foreach ($o in $m) { EncolarMedicion $o -Primero }   # por si alguna se marco y aun no estaba en cola
        ProgresoMedicion
        $a.Plan = $null; $a.Win.FindName('BtnSig').IsEnabled = $false; return
    }
    $a.ProgMed = $null
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
    $a.NubesPlan = @(foreach ($n in @(NubesElegidas)) { [pscustomobject]@{ Nube = $n; P = (UnidadesParaNube $n $units $a.Tam) } })
    $ahorro = [int64]0; foreach ($u in $units) { if ($a.Total.ContainsKey($u.Clave)) { $ahorro += $a.Total[$u.Clave] - $a.Tam[$u.Clave] } }
    PintarPlan $panel $plan $ahorro $discos $a.NubesPlan
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
    $nubes = @($a.NubesPlan | ForEach-Object { $_.Nube })
    foreach ($n in @($nubes | Where-Object { $_.Nueva })) {
        if ($n.Tipo -eq 'rclone') { $msg += "`n`n$([char]0x2022) Se subirá una copia de lo imprescindible a '$($n.Nombre)' directamente$(if ($n.Cifrado -eq 'si') { ', cifrada con tu contraseña' })." }
        else { $msg += "`n`n$([char]0x2022) Se guardará una copia de lo imprescindible en '$($n.Nombre)' (carpeta $(Join-Path $n.RaizSync $CarpetaNube)). La sube $($n.Proveedor)." }
    }
    foreach ($n in @(LeerNubes | Where-Object { @($nubes | ForEach-Object { $_.Id }) -notcontains $_.Id })) { $msg += "`n`n$([char]0x2022) Se dejará de copiar en '$($n.Nombre)'. Lo que ya hay en la nube no se borra." }
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
    # Nubes: las nuevas reciben su Id y su carpeta BackupApp con la marca
    foreach ($n in $nubes) {
        if ($n.Id -like 'nube:*') { $n.Id = [guid]::NewGuid().ToString() }
        if ($n.Nueva -and $n.Tipo -ne 'rclone') { try { $r = RutaNube $n; New-Item -ItemType Directory -Path $r -Force | Out-Null; EscribirMarca $r $n.Id $n.Nombre } catch {} }
    }
    GuardarNubes $nubes
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
            <TextBlock Margin="16,0,0,0" VerticalAlignment="Center" TextWrapping="Wrap" Foreground="{DynamicResource Texto2}" FontSize="12" Text="¿Acabas de conectar un disco o de instalar tu nube? Pulsa Actualizar. Puedes seguir sin disco: el plan te dirá cuál comprar."/>
          </DockPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0,0,10,0">
            <StackPanel>
              <StackPanel x:Name="ListaDiscos"/>
              <TextBlock Text="En la nube" FontSize="18" FontWeight="SemiBold" Margin="0,22,0,2"/>
              <TextBlock Foreground="{DynamicResource Texto2}" TextWrapping="Wrap" Margin="0,0,0,12" Text="Una copia extra de lo más importante fuera de casa, por si le pasa algo al PC y al disco a la vez. Se guarda en la carpeta de tu servicio y su programa la sube, o va directa a tu cuenta (y cifrada, si quieres) si la conectas aquí sin instalar nada."/>
              <StackPanel x:Name="ListaNubes"/>
              <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                <Button x:Name="BtnDirecta" Content="+  Conectar una cuenta directamente" Margin="0,0,8,0"/>
                <Button x:Name="BtnOtraNube" Content="+  Otra carpeta en la nube o NAS"/>
              </StackPanel>
              <StackPanel x:Name="ComoConectar" Margin="0,18,0,0"/>
            </StackPanel>
          </ScrollViewer>
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
    @{ Nombre = 'Discos y nube'; Titulo = '¿Dónde se guarda la copia?'; Desc = 'Marca los discos que quieres usar para el backup (mejor si son externos) y, si quieres, una nube para tener además una copia de lo imprescindible.' },
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
    if ($p -eq 1) { $w.Cursor = [Windows.Input.Cursors]::Wait; LlenarDiscos; LlenarNubes; $w.Cursor = $null }
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
            Cola = (New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'); Medidor = $null; ProgMed = $null; Encolado = @{}
            Alta = (New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'); Baja = (New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]')
            Estado = [hashtable]::Synchronized(@{ Clave = $null; Contador = (New-Object 'long[]' 1); Hechas = [hashtable]::Synchronized(@{}) })
            Errores = @{}; UltimoGuardado = [datetime]::MinValue
            AlTerminar = $alTerminar; FilasDiscos = $null; SinPreguntar = $false; Iniciado = $false
            FilasNubes = $null; DecisionNube = @{}; NubesManuales = (New-Object 'System.Collections.Generic.List[object]'); NubesPlan = @() }
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
    $w.FindName('BtnActualizar').add_Click({ LlenarDiscos; LlenarNubes })
    $w.FindName('BtnOtraNube').add_Click({ AnadirNubeManual })
    $w.FindName('BtnDirecta').add_Click({ MostrarConectarDirecta })
    $w.FindName('BtnAtras').add_Click({ IrAPaso ($script:asis.Paso - 1) })
    $w.FindName('BtnSig').add_Click({ Siguiente })
    $w.FindName('BtnCancelar').add_Click({ $script:asis.Win.Close() })

    # Resultados de la medicion en segundo plano
    $a.Timer = New-Object Windows.Threading.DispatcherTimer; $a.Timer.Interval = [TimeSpan]::FromMilliseconds(400)
    $a.Timer.add_Tick({
        $a = $script:asis; $r = $null; $hubo = $false
        while ($a.Cola.TryDequeue([ref]$r)) {
            $a.Tam[$r.Clave] = [int64]$r.BytesBackup; $a.Total[$r.Clave] = [int64]$r.Bytes; $hubo = $true
            if ($r.Error) { $a.Errores[$r.Clave] = $r.Error }
        }
        # Lo medido se guarda sobre la marcha (cada pocos segundos): si se cierra el asistente, no hay que repetirlo
        if ($hubo -and ((Get-Date) - $a.UltimoGuardado).TotalSeconds -ge 5) { GuardarTamanosMedidos; $a.UltimoGuardado = Get-Date }
        AsegurarMedidor
        $midiendo = [bool]$a.Estado.Clave
        if ($hubo -or $midiendo) { RefrescarTamanos }
        if ($a.Paso -eq 2 -and -not $a.Plan) { if ($hubo) { CalcularPlan } elseif ($midiendo) { ProgresoMedicion } }
    })
    $w.add_Closed({
        $a = $script:asis; $a.Timer.Stop()
        if (-not $a.Guardado) { GuardarTamanosMedidos }
        if ($a.Medidor) { try { $a.Medidor.PS.Stop(); $a.Medidor.PS.Dispose() } catch {} }
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
