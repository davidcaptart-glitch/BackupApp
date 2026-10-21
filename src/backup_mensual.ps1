# ============================================================
#  BACKUP
#  Copia diferencial (espejo) a uno o varios discos de backup.
#  - Detecta solo los discos registrados que esten conectados
#  - Cada carpeta vive en un disco; el reparto es automatico
#  - Solo copia lo nuevo o modificado y borra lo que ya no existe
#  - Comprime con NTFS y propone liberar carpetas sin uso
#  - Copia extra de lo imprescindible en las carpetas de la nube (OneDrive, Dropbox...)
#  -SoloNube: solo la copia en la nube que toque, sin ventanas (la lanza el icono cada semana)
#  Muestra una ventana de progreso con "Detener"; lo copiado se conserva y la siguiente copia sigue donde se quedo.
# ============================================================

param([switch]$DesdeBandeja, [switch]$SoloNube, [string]$Archivar)   # -Archivar <lista.json>: copiar a _ARCHIVO y borrar del PC (Explorar discos)

. (Join-Path $PSScriptRoot "config.ps1")
. (Join-Path $PSScriptRoot "ui.ps1")

function GB($b) { if ([math]::Abs([double]$b) -lt 1GB) { "{0:N0} MB" -f ($b / 1MB) } else { "{0:N1} GB" -f ($b / 1GB) } }
function Aviso($titulo, $texto, $botones = @('Aceptar'), $primario = $null) { return (Dialogo $null $titulo $texto $botones $primario) }

New-Item -ItemType Directory -Path $CarpetaLogs -Force | Out-Null
# La medicion de tamanos lee los mismos discos: se para mientras se copia (vuelve a medir otro dia).
# El mutex avisa a medir_tamanos.ps1 de que hay una copia en marcha.
$script:mutexCopia = New-Object System.Threading.Mutex($false, "BackupAppCopia")
try { [void]$script:mutexCopia.WaitOne(0) } catch [Threading.AbandonedMutexException] {}
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*medir_tamanos.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
$Log =Join-Path $CarpetaLogs ("backup_" + (Get-Date -Format "yyyy-MM-dd_HHmm") + ".log")

# ---------- Ventana de progreso ----------
$script:detener = $false
$script:prog = $null; $script:cerrandoProgreso = $false
function AbrirProgreso {
    if ($SoloNube) { return }
    $w = NuevaVentana @"
<Window $VentanaBase Title="Copia de seguridad" Width="560" SizeToContent="Height" ResizeMode="CanMinimize" WindowStartupLocation="CenterScreen">
  <StackPanel Margin="28,24,28,22">
    <DockPanel>
      <TextBlock x:Name="Porcentaje" DockPanel.Dock="Right" FontSize="20" FontWeight="SemiBold" Foreground="{DynamicResource Acento}" Margin="12,0,0,0"/>
      <TextBlock x:Name="Titulo" FontSize="20" FontWeight="SemiBold" Text="Preparando la copia..." TextTrimming="CharacterEllipsis"/>
    </DockPanel>
    <TextBlock x:Name="Detalle" Foreground="{DynamicResource Texto2}" Margin="0,6,0,14" TextTrimming="CharacterEllipsis"/>
    <ProgressBar x:Name="Barra" Height="6" Minimum="0" Maximum="1" BorderThickness="0" Foreground="{DynamicResource Acento}" Background="{DynamicResource Barra}"/>
    <TextBlock x:Name="Cuenta" Foreground="{DynamicResource Texto2}" Margin="0,10,0,0" TextWrapping="Wrap"/>
    <TextBlock Margin="0,12,0,0" FontSize="11.5" Foreground="{DynamicResource Texto2}" TextWrapping="Wrap" Text="Puedes seguir usando el PC. Si detienes la copia, lo ya copiado se conserva y la próxima vez seguirá donde se quedó."/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="BtnAbrir" Content="Abrir BackupApp" Margin="0,0,8,0"/>
      <Button x:Name="BtnDetener" Content="Detener"/>
    </StackPanel>
  </StackPanel>
</Window>
"@
    $w.FindName('BtnDetener').add_Click({ param($s, $e) $script:detener = $true; $s.IsEnabled = $false; $s.Content = "Deteniendo..." })
    # El icono abre su ventana principal (plan, liberar espacio, explorar) sin parar la copia
    $w.FindName('BtnAbrir').add_Click({ Set-Content -LiteralPath (Join-Path $Datos "abrir.senal") 'x' -ErrorAction SilentlyContinue })
    $w.add_Closing({ param($s, $e) if (-not $script:cerrandoProgreso) { $e.Cancel = $true; $script:detener = $true } })
    $w.Show()
    $script:prog = $w
    Bombear
}
function Progreso($titulo, $detalle, [double]$fraccion, $cuenta = '') {
    if ($env:BACKUPAPP_PRUEBA -and $cuenta -ne $script:ultimaCuenta) { $script:ultimaCuenta = $cuenta; [Console]::WriteLine("[PROGRESO] {0:P0} | $detalle | $cuenta" -f $fraccion) }
    if (-not $script:prog) { return }
    $w = $script:prog
    if ($titulo) { $w.FindName('Titulo').Text = $titulo }
    $f = [math]::Max(0.0, [math]::Min(1.0, $fraccion))
    $w.FindName('Detalle').Text = $detalle; $w.FindName('Barra').Value = $f; $w.FindName('Cuenta').Text = $cuenta
    $w.FindName('Porcentaje').Text = if ($f -gt 0) { "{0:N0} %" -f [math]::Floor($f * 100) } else { "" }
    Bombear
}
function CerrarProgreso { if ($script:prog) { $script:cerrandoProgreso = $true; $script:prog.Close(); $script:prog = $null } }
function Bombear {
    [Windows.Forms.Application]::DoEvents()
    # «Ver la copia» en la ventana principal: se trae la ventana al frente, centrada en la pantalla principal
    # (minimizada o en otro monitor no se encontraba)
    $sv = Join-Path $Datos "ver_copia.senal"
    if ($script:prog -and (Test-Path -LiteralPath $sv)) {
        Remove-Item -LiteralPath $sv -Force -ErrorAction SilentlyContinue
        $w = $script:prog; $w.WindowState = 'Normal'
        $a = [Windows.SystemParameters]::WorkArea
        $w.Left = $a.Left + ($a.Width - $w.ActualWidth) / 2; $w.Top = $a.Top + ($a.Height - $w.ActualHeight) / 2
        $w.Topmost = $true; [void]$w.Activate(); $w.Topmost = $false
    }
}

# ---------- Progreso por GB: se lee el registro de robocopy (/BYTES) mientras copia ----------
$script:copia = $null
function EmpezarProgresoCopia([int64]$total) {
    $pos = if (Test-Path -LiteralPath $Log) { (Get-Item -LiteralPath $Log).Length } else { 0 }
    $script:copia = @{ Total = $total; Hecho = [int64]0; Actual = [int64]0; Archivo = ''; Pos = [int64]$pos
                       Hist = (New-Object 'System.Collections.Generic.Queue[object]'); Visto = [datetime]::MinValue }
}
function LeerLogCopia {
    $c = $script:copia; if (-not $c -or -not (Test-Path -LiteralPath $Log)) { return }
    try {
        $fs = [IO.File]::Open($Log, 'Open', 'Read', 'ReadWrite')
        try {
            if ($fs.Length -le $c.Pos) { return }
            [void]$fs.Seek($c.Pos, 'Begin'); $buf = New-Object byte[] ([int][math]::Min(4MB, $fs.Length - $c.Pos)); $n = $fs.Read($buf, 0, $buf.Length)
        } finally { $fs.Close() }
        $txt = [Text.Encoding]::Default.GetString($buf, 0, $n)
        $fin = $txt.LastIndexOf("`n"); if ($fin -lt 0) { return }      # solo lineas completas
        $c.Pos += [Text.Encoding]::Default.GetByteCount($txt.Substring(0, $fin + 1))
        foreach ($l in $txt.Substring(0, $fin).Split("`n")) {
            # "    Nuevo arch    443547648    D:\ruta\archivo.mov"  (las de *EXTRA son borrados, no copias)
            if ($l -match '^\s*([^\t]*?)\s*\t+\s*(\d+)\s*\t(.+?)\s*$' -and $Matches[1] -notmatch 'EXTRA') { $c.Actual += [int64]$Matches[2]; $c.Archivo = Split-Path $Matches[3] -Leaf }
        }
    } catch {}
}
function TextoProgresoCopia {
    $c = $script:copia; $hecho = $c.Hecho + $c.Actual; $ahora = Get-Date
    $c.Hist.Enqueue(@($ahora, $hecho)); while ($c.Hist.Count -gt 2 -and ($ahora - $c.Hist.Peek()[0]).TotalSeconds -gt 30) { [void]$c.Hist.Dequeue() }
    $p = $c.Hist.Peek(); $seg = ($ahora - $p[0]).TotalSeconds
    $vel = if ($seg -ge 5) { ($hecho - $p[1]) / $seg } else { 0 }
    $txt = if ($c.Total -gt 0) { "$(GB $hecho) de $(GB $c.Total)" } else { "$(GB $hecho) copiados" }
    if ($vel -gt 0 -and $c.Total -gt 0) {
        $txt += "  $([char]0x00B7)  {0:N0} MB/s" -f ($vel / 1MB)
        $falta = [math]::Max(0.0, [double]($c.Total - $hecho)) / $vel
        $txt += "  $([char]0x00B7)  quedan " + $(if ($falta -ge 5400) { "unas {0:N0} h" -f ($falta / 3600) } elseif ($falta -ge 90) { "unos {0:N0} min" -f ($falta / 60) } else { "menos de 2 min" })
    }
    return $txt
}
$script:ssd = @{}
function EsSSD($ruta) {
    # Para decidir cuantos archivos se copian a la vez: en discos duros, de uno en uno o de dos en dos va mas rapido
    $l = "$ruta".Substring(0, 1).ToUpper()
    if (-not $script:ssd.ContainsKey($l)) {
        $v = $false
        try { $d = Get-Partition -DriveLetter $l -ErrorAction Stop | Get-Disk -ErrorAction Stop; $v = (Get-PhysicalDisk | Where-Object { $_.DeviceId -eq "$($d.Number)" }).MediaType -eq 'SSD' } catch {}
        $script:ssd[$l] = $v
    }
    return $script:ssd[$l]
}
function Hilos($origen, $destino) { if ((EsSSD $origen) -and (EsSSD $destino)) { '/MT:8' } else { '/MT:2' } }

# Quita la marca de compresion de BACKUP y de todas sus carpetas (no toca los archivos ya copiados),
# para que lo que se copie a partir de ahora no se comprima. compact acepta varias carpetas por llamada.
function QuitarCompresion($raiz) {
    Progreso "Preparando el disco..." "Quitando la compresión de las carpetas para copiar más rápido" 0
    $dirs = New-Object Collections.Generic.List[string]; $dirs.Add($raiz.TrimEnd('\'))
    try { foreach ($d in [IO.Directory]::EnumerateDirectories($raiz, '*', [IO.SearchOption]::AllDirectories)) { $dirs.Add($d) } } catch {}
    $lote = New-Object Collections.Generic.List[string]; $largo = 0; $n = 0
    foreach ($d in $dirs) {
        $lote.Add($d); $largo += $d.Length + 3; $n++
        if ($largo -gt 6000 -or $n -eq $dirs.Count) {
            & compact.exe /u /i /q @($lote) | Out-Null
            $lote.Clear(); $largo = 0
            Progreso "Preparando el disco..." "Quitando la compresión de las carpetas para copiar más rápido" ($n / $dirs.Count)
        }
    }
    Add-Content $Log "Compresion NTFS quitada de $($dirs.Count) carpetas de $raiz"
}

# robocopy en un proceso aparte, para que la ventana siga respondiendo y se pueda detener
function Robo([string[]]$argumentos) {
    $args2 = ($argumentos | ForEach-Object { if ($_ -match '[\s]' -and $_ -notmatch '^/') { "`"$_`"" } elseif ($_ -match '^(/LOG\+:)(.+)$') { "$($Matches[1])`"$($Matches[2])`"" } else { $_ } }) -join ' '
    $pi = New-Object Diagnostics.ProcessStartInfo 'robocopy.exe', $args2
    $pi.UseShellExecute = $false; $pi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($pi)
    $ultimo = [datetime]::MinValue
    while (-not $p.WaitForExit(150)) {
        Bombear
        if ($script:detener) { try { $p.Kill() } catch {}; $p.WaitForExit(); return 16 }
        if ($script:copia -and ((Get-Date) - $ultimo).TotalMilliseconds -ge 1000) {
            $ultimo = Get-Date; LeerLogCopia
            $c = $script:copia
            $fr = if ($c.Total -gt 0) { [math]::Min(0.999, ($c.Hecho + $c.Actual) / $c.Total) } else { 0 }
            Progreso $null "$($script:unidadActual)$(if ($c.Archivo) { "  $([char]0x00B7)  $($c.Archivo)" })" $fr (TextoProgresoCopia)
        }
    }
    if ($script:copia) { LeerLogCopia }
    return $p.ExitCode
}

# ---------- Elegir que carpetas sin uso se borran del PC (quedan archivadas en el disco) ----------
function ElegirCarpetasALiberar($candidatas, $disco) {
    if ($env:BACKUPAPP_PRUEBA) { [Console]::WriteLine("[ELEGIR] $(@($candidatas).Count) carpetas sin uso -> todas"); return $candidatas }
    $w = NuevaVentana @"
<Window $VentanaBase Title="Liberar espacio en tu PC" Width="780" Height="640" MinWidth="600" MinHeight="420" WindowStartupLocation="CenterScreen" Topmost="True">
  <Grid Margin="32,26,32,22">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock x:Name="Titulo" FontSize="24" FontWeight="SemiBold" FontFamily="Segoe UI Variable Display, Segoe UI" TextWrapping="Wrap"/>
    <TextBlock x:Name="Desc" Grid.Row="1" Foreground="{DynamicResource Texto2}" Margin="0,6,0,16" TextWrapping="Wrap"/>
    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0,0,10,0"><StackPanel x:Name="Lista"/></ScrollViewer>
    <DockPanel Grid.Row="3" Margin="0,18,0,0">
      <TextBlock x:Name="Total" VerticalAlignment="Center" FontWeight="SemiBold"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="BtnNada" Content="No borrar nada" Margin="0,0,8,0"/>
        <Button x:Name="BtnSeguir" Content="Continuar" Style="{DynamicResource Primario}" MinWidth="120" IsEnabled="False"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@
    $total = ($candidatas | Measure-Object Bytes -Sum).Sum
    $w.FindName('Titulo').Text = "$($candidatas.Count) carpetas llevan más de $MesesSinUso meses sin usarse ($(GB $total))"
    $w.FindName('Desc').Text = "Ya tienen copia en «$($disco.Nombre)». Si las borras de tu PC ganas espacio, y en el disco se guardan aparte ($($disco.Letra)\$CarpetaBackup\_ARCHIVO) para que no se pierdan nunca. Marca las que quieras borrar del PC."
    $script:lib = @{ Win = $w; Items = @($candidatas | Sort-Object Bytes -Descending); Checks = @(); Elegidas = @() }
    foreach ($c in $script:lib.Items) {
        $chk = New-Object Windows.Controls.CheckBox
        $chk.add_Click({
            $l = $script:lib; $b = [int64]0; $n = 0
            for ($i = 0; $i -lt $l.Items.Count; $i++) { if ($l.Checks[$i].IsChecked) { $b += $l.Items[$i].Bytes; $n++ } }
            $l.Win.FindName('Total').Text = $(if ($n) { "$n marcadas $([char]0x00B7) $(GB $b)" } else { "" })
            $l.Win.FindName('BtnSeguir').IsEnabled = $n -gt 0
        })
        $script:lib.Checks += $chk
        $info = Apilar @((Texto $c.Carpeta 14 'SemiBold'), (Texto "$($c.Ruta)   $([char]0x00B7)   último cambio $($c.Ultimo.ToString('dd/MM/yyyy'))" 11.5 'Normal' 'Texto2'))
        $info.Margin = '12,0,12,0'
        [void]$w.FindName('Lista').Children.Add((Tarjeta (Fila @($chk, $info, (Texto (GB $c.Bytes) 15 'SemiBold')) @('Auto', '*', 'Auto'))))
    }
    $w.FindName('BtnNada').add_Click({ $script:lib.Win.Close() })
    $w.FindName('BtnSeguir').add_Click({
        $l = $script:lib; $l.Elegidas = @(for ($i = 0; $i -lt $l.Items.Count; $i++) { if ($l.Checks[$i].IsChecked) { $l.Items[$i] } }); $l.Win.Close()
    })
    [void]$w.ShowDialog()
    return $script:lib.Elegidas
}

# ---------- Espejo de la copia en una carpeta de la nube ----------
# Se conservan las unidades elegidas y las carpetas intermedias hasta ellas; lo demas, dentro de BackupApp, se quita.
function EspejoCarpetaNube($raiz, $rel, $cj) {
    $abs = Join-Path $raiz $rel
    if (-not (Test-Path -LiteralPath $abs)) { return }
    foreach ($d in @(Get-ChildItem -LiteralPath $abs -Directory -Force -ErrorAction SilentlyContinue)) {
        $r = Join-Path $rel $d.Name; $k = $r.ToLower()
        if ($cj.Unidades.ContainsKey($k)) { continue }
        if ($cj.Ancestros.ContainsKey($k)) { EspejoCarpetaNube $raiz $r $cj; continue }
        Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not $cj.Sueltos.ContainsKey($rel.ToLower())) { Get-ChildItem -LiteralPath $abs -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
}

# ---------- Recordar por donde iba una copia interrumpida ----------
$FicheroCopiaEnCurso = Join-Path $Datos "copia_en_curso.json"
function LeerCopiaEnCurso($idDisco) {
    # Subcarpetas ya terminadas en una copia a este disco que se interrumpio hace menos de 7 dias
    $h = @{}
    if (Test-Path -LiteralPath $FicheroCopiaEnCurso) {
        try {
            $j = [IO.File]::ReadAllText($FicheroCopiaEnCurso) | ConvertFrom-Json
            if ($j.Disco -eq $idDisco -and ((Get-Date) - [datetime]$j.Inicio).TotalDays -lt 7) { foreach ($k in $j.Hechas) { $h[$k] = $true } }
        } catch {}
    }
    return $h
}
function GuardarCopiaEnCurso($idDisco, $hechas) {
    $inicio = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    if (Test-Path -LiteralPath $FicheroCopiaEnCurso) { try { $j = [IO.File]::ReadAllText($FicheroCopiaEnCurso) | ConvertFrom-Json; if ($j.Disco -eq $idDisco) { $inicio = $j.Inicio } } catch {} }
    try { [IO.File]::WriteAllText($FicheroCopiaEnCurso, ([pscustomobject]@{ Disco = $idDisco; Inicio = $inicio; Hechas = @($hechas.Keys) } | ConvertTo-Json)) } catch {}
}
function BorrarCopiaEnCurso { Remove-Item -LiteralPath $FicheroCopiaEnCurso -Force -ErrorAction SilentlyContinue }

# ---------- Archivar: lo que el usuario elige en "Explorar discos" ----------
# Se copia a <disco>\BACKUP\_ARCHIVO (sin /MIR: nunca se borra nada del archivo), se comprueba que no falta nada
# y solo entonces se borra del PC. Se apunta en _ARCHIVO\indice_archivo.csv.
function ArchivarLista {
    $j = [IO.File]::ReadAllText($Archivar) | ConvertFrom-Json
    Remove-Item -LiteralPath $Archivar -Force -ErrorAction SilentlyContinue
    $disco = DiscosConectados | Where-Object { $_.Id -eq $j.Disco } | Select-Object -First 1
    if (-not $disco) { [void](Aviso "Conecta el disco de backup" "El disco elegido ya no está conectado. No se ha borrado nada."); return }
    $items = @($j.Items)
    AbrirProgreso
    Progreso "Copiando a «$($disco.Nombre)» y borrando del PC" "Preparando..." 0
    EmpezarProgresoCopia ([int64](($items | ForEach-Object { [int64]$_.Bytes } | Measure-Object -Sum).Sum))
    $hechos = @(); $fallos = @(); $n = 0
    $indice = Join-Path $disco.Raiz "_ARCHIVO\indice_archivo.csv"
    foreach ($it in $items) {
        if ($script:detener) { break }
        $n++; $ruta = $it.Ruta.TrimEnd('\')
        if (-not (Test-Path -LiteralPath $ruta)) { $fallos += "$ruta (ya no existe)"; continue }
        $esDir = Test-Path -LiteralPath $ruta -PathType Container
        $dst = Join-Path $disco.Raiz (Join-Path "_ARCHIVO" (DestinoDe $ruta))
        $script:unidadActual = "$(Split-Path $ruta -Leaf)  ($n de $($items.Count))"
        if ($esDir) {
            $c = Robo @($ruta, $dst, '/E', '/FFT', '/XJ', '/R:1', '/W:2', (Hilos $ruta $disco.Raiz), '/BYTES', '/NP', '/NDL', "/LOG+:$Log")
            $v = if ($c -lt 8 -and -not $script:detener) { Robo @($ruta, $dst, '/E', '/L', '/FFT', '/XJ', '/R:0', '/W:0', '/NJH', '/NJS', '/NFL', '/NDL') } else { 16 }
        } else {
            $c = Robo @((Split-Path $ruta -Parent), (Split-Path $dst -Parent), (Split-Path $ruta -Leaf), '/FFT', '/R:1', '/W:2', '/BYTES', '/NP', '/NDL', "/LOG+:$Log")
            $v = if ($c -lt 8 -and -not $script:detener) { Robo @((Split-Path $ruta -Parent), (Split-Path $dst -Parent), (Split-Path $ruta -Leaf), '/L', '/FFT', '/R:0', '/W:0', '/NJH', '/NJS', '/NFL', '/NDL') } else { 16 }
        }
        $script:copia.Hecho += [int64]$it.Bytes; $script:copia.Actual = 0
        if ($script:detener) { break }
        # Comprobacion: el codigo 1 (o mas de 8) significa que aun faltaria copiar algo; entonces no se borra
        if ($c -ge 8 -or ($v -band 1) -or $v -ge 8) { $fallos += "$ruta (la copia no se pudo completar o no coincide: no se ha borrado)"; continue }
        try { Remove-Item -LiteralPath $ruta -Recurse -Force -ErrorAction Stop }
        catch { $fallos += "$ruta (copiada, pero no se pudo borrar del PC: ¿algún archivo abierto?)"; continue }
        $hechos += $it
        $rep = LeerReparto; foreach ($k in @($rep.Keys)) { if (DentroDe $k $ruta) { [void]$rep.Remove($k) } }; GuardarReparto $rep
        [pscustomobject]@{ Fecha = (Get-Date -Format "yyyy-MM-dd"); Original = $ruta; Guardado_en = $dst; GB = [math]::Round([int64]$it.Bytes / 1GB, 2) } |
            Export-Csv -Path $indice -Append -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }
    $script:copia = $null
    CerrarProgreso
    $txt = "Copiados a «$($disco.Nombre)» y borrados del PC: $($hechos.Count) de $($items.Count) ($(GB (($hechos | ForEach-Object { [int64]$_.Bytes } | Measure-Object -Sum).Sum)) liberados).`n`nEstán en $($disco.Letra)\$CarpetaBackup\_ARCHIVO."
    if ($script:detener) { $txt += "`n`nLo detuviste: lo que faltaba sigue en tu PC sin tocar." }
    if ($fallos) { $txt += "`n`nNo se borraron:`n" + (($fallos | ForEach-Object { "$([char]0x2022) $_" }) -join "`n") }
    [void](Aviso $(if ($fallos) { "Terminado con avisos" } else { "Terminado" }) $txt)
}
if ($Archivar) { ArchivarLista; exit }

# 1) Hay carpetas y discos registrados?
if (-not $Carpetas) {
    [void](Aviso "Todavía no hay nada que copiar" "Aún no has elegido qué carpetas copiar. Haz clic derecho en el escudo > Asistente de configuración.")
    exit
}
$registrados = @(LeerDiscos)
$nubes = @(LeerNubes)
if ($SoloNube) { $registrados = @() }
elseif (-not $registrados -and -not $nubes) {
    [void](Aviso "No hay discos de backup" "Aún no tienes ningún disco de backup. Conecta un disco externo: el escudo te ofrecerá usarlo. También puedes abrir el asistente desde el menú del escudo.")
    exit
}

# 2) Esperar a que haya al menos un disco registrado conectado
$conectados = if ($registrados) { @(DiscosConectados) } else { @() }
$pendientes = @($registrados | Where-Object { DiscoToca $_ } | ForEach-Object { $_.Nombre })
if ($registrados -and (-not $DesdeBandeja -or -not $conectados)) {
    while (-not $conectados) {
        $txt = "Tus discos de backup: " + (($registrados | ForEach-Object { $_.Nombre }) -join ", ") + "."
        if ($pendientes) { $txt += " Toca copiar: " + ($pendientes -join ", ") + "." }
        $txt += "`n`nConecta uno y pulsa «Ya está conectado». Si lo dejas para más tarde, el escudo te lo recordará."
        $r = Aviso "Conecta un disco de backup" $txt @('Más tarde', 'Ya está conectado') 'Ya está conectado'
        if ($r -ne 'Ya está conectado') { if ($nubes) { break } else { exit } }   # sin disco, al menos la copia en la nube
        $conectados = @(DiscosConectados)
    }
}

$resumen  = @()
$hayError = $false
AbrirProgreso

# Si compras discos de 1 o 2 TB, lo que ha crecido y ya no cabe en uno se divide por sus subcarpetas
if ($conectados) { [void](DividirSegunAjuste) }
foreach ($disco in $conectados) {
    if ($script:detener) { break }
    Add-Content $Log "===== DISCO $($disco.Nombre) ($($disco.Letra)) ====="
    Progreso "Copiando en «$($disco.Nombre)»" "Preparando el disco $($disco.Letra)..." 0
    New-Item -ItemType Directory -Path $disco.Raiz -Force | Out-Null

    # 2b) Quitar del disco lo que el usuario saco de el en "Editar el plan" (deja sitio antes de copiar)
    $pend = @(LeerQuitar); $mios = @($pend | Where-Object { $_.Disco -eq $disco.Id })
    if ($mios) {
        Progreso $null "Dejando sitio: quitando del disco $($mios.Count) carpetas que ya no van aquí..." 0
        foreach ($q in $mios) {
            $dst = Join-Path $disco.Raiz $q.Ruta
            if (-not (Test-Path -LiteralPath $dst)) { continue }
            if ([int]$q.Sueltos) { Get-ChildItem -LiteralPath $dst -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
            else { Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue }
            Add-Content $Log "Quitado del disco (ya no va aqui): $dst"
        }
        GuardarQuitar @($pend | Where-Object { $_.Disco -ne $disco.Id })
        $resumen += "$($disco.Nombre): quitadas $($mios.Count) carpetas que ya no van a este disco ($(GB (($mios | ForEach-Object { [int64]$_.Bytes } | Measure-Object -Sum).Sum)))"
    }

    # 3) Sin compresion NTFS: fotos y videos no se comprimen y en discos USB la copia iba 4 veces mas lenta.
    #    Las versiones antiguas comprimian BACKUP: se quita la marca de las carpetas (lo ya copiado se queda igual).
    if (([IO.File]::GetAttributes($disco.Raiz) -band [IO.FileAttributes]::Compressed)) { QuitarCompresion $disco.Raiz }

    # 4) Reparto: asignar carpetas nuevas y quedarnos con las de este disco
    $rep = AsignarNuevas
    $unidades = @(UnidadesActuales | Where-Object { $rep[$_.Clave] -eq $disco.Id })

    # 5) Aviso de espacio previsto (si falta algun tamano, se mide ahora: tambien sirve para el progreso)
    $tam = TamanosDe $unidades
    $previsto = ($unidades | ForEach-Object { [int64]$tam[$_.Clave] } | Measure-Object -Sum).Sum
    if ($previsto -gt $disco.Capacidad) {
        $r = Aviso "«$($disco.Nombre)» se queda pequeño" "A este disco le corresponden $(GB $previsto), pero solo tiene $(GB $disco.Capacidad). Conviene añadir otro disco: lo nuevo irá al que tenga más sitio.`n`n¿Copiar igualmente lo que quepa?" @('No', 'Copiar igualmente') 'Copiar igualmente'
        if ($r -ne 'Copiar igualmente') { $resumen += "$($disco.Nombre): no se copió por falta de espacio"; continue }
    }

    # 6) Copia diferencial de cada unidad (con progreso por GB, velocidad y tiempo que falta)
    # Si una copia anterior a este disco se interrumpio, se saltan las subcarpetas que ya termino (copia_en_curso.json)
    $hechas = LeerCopiaEnCurso $disco.Id
    $errores = @(); $n = 0
    EmpezarProgresoCopia ([int64]$previsto)
    if ($hechas.Count) { Progreso "Continuando la copia en «$($disco.Nombre)»" "Se quedó a medias: $($hechas.Count) de $($unidades.Count) carpetas ya estaban copiadas" 0 }
    foreach ($u in $unidades) {
        if ($script:detener) { break }
        $n++
        if ($hechas.ContainsKey($u.Clave)) { $script:copia.Hecho += [int64]$tam[$u.Clave]; continue }
        $script:unidadActual = "$($u.Carpeta.Origen | Split-Path -Leaf)  $([char]0x203A)  $(if ($u.Rel) { $u.Rel } else { $u.Nombre })  ($n de $($unidades.Count))"
        Progreso $null $script:unidadActual $(if ($script:copia.Total -gt 0) { $script:copia.Hecho / $script:copia.Total } else { ($n - 1) / [math]::Max(1, $unidades.Count) }) (TextoProgresoCopia)
        if ($u.Tipo -eq 'carpeta') {
            $dst = Join-Path $disco.Raiz (DestinoUnidad $u)
            # Lo que ya esta en el disco cuenta como hecho (robocopy no apunta los archivos que se salta)
            if (Test-Path -LiteralPath $dst) {
                Progreso $null "$($script:unidadActual)  $([char]0x00B7)  mirando lo que ya está copiado..." $(if ($script:copia.Total -gt 0) { $script:copia.Hecho / $script:copia.Total } else { 0 }) (TextoProgresoCopia)
                $script:copia.Actual = [int64][math]::Min([double](Analizar $dst).Bytes, [double]$tam[$u.Clave])
                $script:copia.Hist.Clear()   # el salto no es velocidad de copia
            }
            $c = Robo (@($u.Clave, $dst, '/XD') + $Excluir + @('/MIR', '/FFT', '/XJ', '/R:1', '/W:2', (Hilos $u.Clave $disco.Raiz), '/BYTES', '/NP', '/NDL', "/LOG+:$Log"))
            if ($c -ge 8 -and -not $script:detener) { $errores += "$($u.Clave) (código $c)" }
        } else {
            # Archivos sueltos de la raiz: copiar solo los de primer nivel y borrar los que ya no existen
            $dst = Join-Path $disco.Raiz (DestinoUnidad $u)
            $c = Robo @($u.Dir, $dst, '/FFT', '/R:1', '/W:2', '/BYTES', '/NP', '/NDL', "/LOG+:$Log")
            if ($c -ge 8 -and -not $script:detener) { $errores += "$($u.Clave) (código $c)" }
            Get-ChildItem -LiteralPath $dst -File -Force -ErrorAction SilentlyContinue |
                Where-Object { -not (Test-Path -LiteralPath (Join-Path $u.Dir $_.Name)) } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
        if ($script:detener) { break }   # a medias: no cuenta como hecha
        # Unidad terminada: cuenta entera (en las copias siguientes solo se copia lo que ha cambiado) y se apunta
        $script:copia.Hecho += [math]::Max([int64]$tam[$u.Clave], $script:copia.Actual); $script:copia.Actual = 0; $script:copia.Archivo = ''
        if ($c -lt 8) { $hechas[$u.Clave] = $true; GuardarCopiaEnCurso $disco.Id $hechas }
        if ($env:BACKUPAPP_PRUEBA_PARAR -and $hechas.Count -ge [int]$env:BACKUPAPP_PRUEBA_PARAR) { $script:detener = $true }   # pruebas: simula pulsar Detener
    }
    $script:copia = $null
    if (-not $script:detener) { BorrarCopiaEnCurso }   # copia completa: la proxima empieza de cero
    if ($script:detener) { $resumen += "$($disco.Nombre): copia detenida en la carpeta $n de $($unidades.Count). Lo copiado se conserva."; break }

    # 7) Espejo: borrar del disco las carpetas que ya no existen en el origen
    $actuales = @{}; UnidadesActuales | ForEach-Object { $actuales[$_.Clave] = $true }
    foreach ($k in @($rep.Keys)) {
        if ($rep[$k] -ne $disco.Id -or $actuales.ContainsKey($k) -or $k.EndsWith('\*')) { continue }
        $c = $Carpetas | Where-Object { DentroDe $k $_.Origen } | Select-Object -First 1
        if (-not $c -or -not (Test-Path -LiteralPath $c.Origen)) { continue }   # si el disco de origen no esta, no tocar nada
        # Sigue en el PC pero ya no es una unidad (la quitaste del plan o la abriste para elegir dentro): su copia se conserva
        if (Test-Path -LiteralPath $k) { [void]$rep.Remove($k); continue }
        $dst = Join-Path $disco.Raiz (Join-Path $c.Destino (RelDe $c $k))
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue }
        $rep.Remove($k)
    }
    GuardarReparto $rep

    # 8) Guardar fecha de copia de este disco
    $lista = @(LeerDiscos)
    foreach ($d in $lista) { if ($d.Id -eq $disco.Id) { $d.UltimaCopia = (Get-Date -Format "yyyy-MM-dd HH:mm"); $d.Capacidad = $disco.Capacidad } }
    GuardarDiscos $lista

    $libre = (New-Object IO.DriveInfo $disco.Letra).AvailableFreeSpace
    if ($errores) {
        $hayError = $true
        $resumen += "$($disco.Nombre) ($($disco.Letra)): con errores en`n   " + ($errores -join "`n   ")
    } else {
        $resumen += "$($disco.Nombre) ($($disco.Letra)): correcto, $($unidades.Count) carpetas, quedan $(GB $libre) libres"
    }

    # ========================================================
    # 9) LIBERAR ESPACIO: carpetas de este disco sin cambios en $MesesSinUso meses
    # ========================================================
    if ($errores) { continue }
    Progreso $null "Buscando carpetas que llevan tiempo sin usarse..." 1 ""
    $limite = (Get-Date).AddMonths(-$MesesSinUso)
    $candidatas = @()
    foreach ($u in ($unidades | Where-Object { $_.Tipo -eq 'carpeta' })) {
        $a = Analizar $u.Clave
        if ($a.Archivos -gt 0 -and $a.Ultimo -lt $limite -and $a.Bytes -ge ($TamMinimoMB * 1MB)) {
            $candidatas += [pscustomobject]@{
                Carpeta = $u.Nombre; Ultimo = $a.Ultimo; Bytes = $a.Bytes; Ruta = $u.Clave
                Backup  = Join-Path $disco.Raiz (DestinoUnidad $u)
                Archivo = Join-Path $disco.Raiz (Join-Path "_ARCHIVO" (DestinoUnidad $u))
            }
        }
    }
    if (-not $candidatas) { continue }

    $elegidas = @(ElegirCarpetasALiberar $candidatas $disco)
    if (-not $elegidas) { continue }
    $bytes = ($elegidas | Measure-Object Bytes -Sum).Sum
    $r = Aviso "¿Borrar del PC $($elegidas.Count) carpetas ($(GB $bytes))?" ("Antes se comprueba que la copia en «$($disco.Nombre)» es idéntica; si no lo es, esa carpeta no se borra. Se guardan en $($disco.Letra)\$CarpetaBackup\_ARCHIVO.`n`n" + (($elegidas | ForEach-Object { "$([char]0x2022) $($_.Ruta)" }) -join "`n")) @('Cancelar', 'Borrar del PC') 'Borrar del PC'
    if ($r -ne 'Borrar del PC') { continue }

    $archivo = Join-Path $disco.Raiz "_ARCHIVO"
    $indice  = Join-Path $archivo "indice_archivo.csv"
    New-Item -ItemType Directory -Path $archivo -Force | Out-Null
    $hechas = @(); $fallos = @(); $n = 0
    foreach ($e in $elegidas) {
        $n++; Progreso "Liberando espacio en tu PC" "Comprobando $($e.Carpeta)..." ($n / $elegidas.Count) "$n de $($elegidas.Count)"
        $c = Robo (@($e.Ruta, $e.Backup, '/XD') + $Excluir + @('/MIR', '/L', '/FFT', '/XJ', '/R:0', '/W:0', '/NJH', '/NJS', '/NFL', '/NDL'))
        if ($c -ne 0 -or -not (Test-Path -LiteralPath $e.Backup)) { $fallos += "$($e.Ruta)  (la copia no coincide, no se borra)"; continue }
        try {
            New-Item -ItemType Directory -Path (Split-Path $e.Archivo -Parent) -Force | Out-Null
            $destArch = $e.Archivo
            if (Test-Path -LiteralPath $destArch) { $destArch += "_" + (Get-Date -Format "yyyyMMdd") }
            Move-Item -LiteralPath $e.Backup -Destination $destArch -ErrorAction Stop
        } catch { $fallos += "$($e.Ruta)  (no se pudo archivar, no se borra)"; continue }
        try {
            Remove-Item -LiteralPath $e.Ruta -Recurse -Force -ErrorAction Stop
            $hechas += $e
            $rep = LeerReparto; $rep.Remove($e.Ruta); GuardarReparto $rep
            [pscustomobject]@{ Fecha = (Get-Date -Format "yyyy-MM-dd"); Original = $e.Ruta; Guardado_en = $destArch; GB = [math]::Round($e.Bytes / 1GB, 2) } |
                Export-Csv -Path $indice -Append -NoTypeInformation -Encoding UTF8 -Delimiter ';'
        } catch { $fallos += "$($e.Ruta)  (archivada, pero no se pudo borrar del PC: ¿algún archivo abierto?)" }
    }
    $resumen += "   Liberados $(GB (($hechas | Measure-Object Bytes -Sum).Sum)) en tu PC ($($hechas.Count) carpetas archivadas)"
    if ($fallos) { $resumen += "   No se borraron:`n   " + ($fallos -join "`n   ") }
}

# ========================================================
# 9b) COPIA EXTRA EN LA NUBE: lo imprescindible que quepa, en <carpeta sincronizada>\BackupApp
# ========================================================
foreach ($n in $nubes) {
    if ($script:detener) { break }
    if (-not (NubeDisponible $n)) { $resumen += "Nube «$($n.Nombre)»: $(if ($n.Tipo -eq 'rclone') { 'no se encuentra la conexión: vuelve a conectarla en el asistente' } else { "no se encuentra su carpeta ($($n.RaizSync))" })"; $hayError = $true; continue }
    $directa = $n.Tipo -eq 'rclone'
    if ($SoloNube -and -not (DiscoToca $n)) { continue }
    Add-Content $Log "===== NUBE $($n.Nombre) ($($n.RaizSync)) ====="
    Progreso "Copiando en la nube «$($n.Nombre)»" "Calculando qué subir..." 0
    if (-not $directa) {
        $ruta = RutaNube $n
        New-Item -ItemType Directory -Path $ruta -Force | Out-Null
        try { EscribirMarca $ruta $n.Id $n.Nombre } catch {}
    }
    MedirNube $n
    $unidades = @(UnidadesActuales)
    $plan = UnidadesParaNube $n $unidades (TamanosDe $unidades)
    $errores = @(); $k = 0; $sel = @($plan.Seleccion); $cj = ConjuntosEspejo $sel
    foreach ($u in $sel) {
        if ($script:detener) { break }
        $k++; Progreso $null "$($u.Carpeta.Origen | Split-Path -Leaf)  $([char]0x203A)  $(if ($u.Rel) { $u.Rel } else { $u.Nombre })" (($k - 1) / [math]::Max(1, $sel.Count)) "$k de $($sel.Count) carpetas"
        if ($directa) {
            # Nube directa: rclone sube (y cifra, si se eligio) sin pasar por ninguna carpeta del PC
            $c = SubirUnidadRclone $u $n $Log
            if ($c -ne 0 -and -not $script:detener) { $errores += "$($u.Clave) (rclone, código $c)" }
            continue
        }
        if ($u.Tipo -eq 'carpeta') {
            $dst = Join-Path $ruta (DestinoUnidad $u)
            $c = Robo (@($u.Clave, $dst, '/XD') + $Excluir + @('/MIR', '/FFT', '/XJ', '/R:1', '/W:2', '/MT:4', '/NP', '/NDL', "/LOG+:$Log"))
            if ($c -ge 8 -and -not $script:detener) { $errores += "$($u.Clave) (código $c)" }
        } else {
            $dst = Join-Path $ruta (DestinoUnidad $u)
            $c = Robo @($u.Dir, $dst, '/FFT', '/R:1', '/W:2', '/NP', '/NDL', "/LOG+:$Log")
            if ($c -ge 8 -and -not $script:detener) { $errores += "$($u.Clave) (código $c)" }
            Get-ChildItem -LiteralPath $dst -File -Force -ErrorAction SilentlyContinue |
                Where-Object { -not (Test-Path -LiteralPath (Join-Path $u.Dir $_.Name)) } | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
    if ($script:detener) { $resumen += "Nube «$($n.Nombre)»: copia detenida. Lo copiado se conserva."; break }
    # Espejo, solo dentro de BackupApp: se quita lo que ya no toca subir (ya no cabe, se borro o cambio de prioridad)
    foreach ($c in $Carpetas) { if ($directa) { EspejoRclone $n $c.Destino $cj } else { EspejoCarpetaNube $ruta $c.Destino $cj } }
    $lista = @(LeerNubes)
    foreach ($x in $lista) { if ($x.Id -eq $n.Id) { $x.UltimaCopia = (Get-Date -Format "yyyy-MM-dd HH:mm"); $x.Ajeno = $n.Ajeno; $x.Capacidad = $n.Capacidad } }
    GuardarNubes $lista
    $linea = "Nube «$($n.Nombre)»: $(if ($errores) { 'con errores' } else { 'correcto' }), $($sel.Count) carpetas ($(GB $plan.Bytes))"
    if ($plan.BytesFuera -gt 0) { $linea += ". No caben $(GB $plan.BytesFuera): amplía el espacio de la nube o baja la prioridad de algo" }
    if (-not $directa -and (NubeActiva $n.Proveedor) -eq $false) { $linea += ". Ojo: $($n.Proveedor) no está abierto; se subirá cuando lo abras" }
    if ($errores) { $hayError = $true; $linea += "`n   " + ($errores -join "`n   ") }
    $resumen += $linea
}
CerrarProgreso

# 10) Resultado final
if ($SoloNube) {
    # Copia automatica: solo se avisa si algo fue mal (el icono muestra la notificacion de que ha terminado)
    if ($hayError) { [void](Aviso "Problemas en la copia en la nube" ($resumen -join "`n")) }
    exit
}
$faltan = @(LeerDiscos | Where-Object { DiscoToca $_ } | ForEach-Object { $_.Nombre })
$txt = ($resumen -join "`n")
if ($faltan -and -not $script:detener) { $txt += "`n`nTodavía toca copiar: " + ($faltan -join ", ") + ". Conéctalo cuando puedas." }
if ($conectados) { $txt += "`n`nAntes de desconectar los discos, usa «Expulsar» en el Explorador." }
$tit = if ($script:detener) { "Copia detenida" } elseif ($hayError) { "Copia terminada con errores" } else { "Copia terminada" }
[void](Aviso $tit $txt)
