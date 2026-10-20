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

param([switch]$DesdeBandeja, [switch]$SoloNube)

. (Join-Path $PSScriptRoot "config.ps1")
. (Join-Path $PSScriptRoot "ui.ps1")

function GB($b) { if ([math]::Abs([double]$b) -lt 1GB) { "{0:N0} MB" -f ($b / 1MB) } else { "{0:N1} GB" -f ($b / 1GB) } }
function Aviso($titulo, $texto, $botones = @('Aceptar'), $primario = $null) { return (Dialogo $null $titulo $texto $botones $primario) }

New-Item -ItemType Directory -Path $CarpetaLogs -Force | Out-Null
$Log = Join-Path $CarpetaLogs ("backup_" + (Get-Date -Format "yyyy-MM-dd_HHmm") + ".log")

# ---------- Ventana de progreso ----------
$script:detener = $false
$script:prog = $null; $script:cerrandoProgreso = $false
function AbrirProgreso {
    if ($SoloNube) { return }
    $w = NuevaVentana @"
<Window $VentanaBase Title="Copia de seguridad" Width="560" SizeToContent="Height" ResizeMode="CanMinimize" WindowStartupLocation="CenterScreen">
  <StackPanel Margin="28,24,28,22">
    <TextBlock x:Name="Titulo" FontSize="20" FontWeight="SemiBold" Text="Preparando la copia..."/>
    <TextBlock x:Name="Detalle" Foreground="{DynamicResource Texto2}" Margin="0,6,0,14" TextTrimming="CharacterEllipsis"/>
    <ProgressBar x:Name="Barra" Height="6" Minimum="0" Maximum="1" BorderThickness="0" Foreground="{DynamicResource Acento}" Background="{DynamicResource Barra}"/>
    <DockPanel Margin="0,16,0,0">
      <TextBlock x:Name="Cuenta" Foreground="{DynamicResource Texto2}" VerticalAlignment="Center"/>
      <Button x:Name="BtnDetener" Content="Detener" HorizontalAlignment="Right"/>
    </DockPanel>
    <TextBlock Margin="0,14,0,0" FontSize="11.5" Foreground="{DynamicResource Texto2}" TextWrapping="Wrap" Text="Puedes seguir usando el PC. Si detienes la copia, lo ya copiado se conserva y la próxima vez seguirá donde se quedó."/>
  </StackPanel>
</Window>
"@
    $w.FindName('BtnDetener').add_Click({ param($s, $e) $script:detener = $true; $s.IsEnabled = $false; $s.Content = "Deteniendo..." })
    $w.add_Closing({ param($s, $e) if (-not $script:cerrandoProgreso) { $e.Cancel = $true; $script:detener = $true } })
    $w.Show()
    $script:prog = $w
    Bombear
}
function Progreso($titulo, $detalle, [double]$fraccion, $cuenta = '') {
    if (-not $script:prog) { return }
    $w = $script:prog
    if ($titulo) { $w.FindName('Titulo').Text = $titulo }
    $w.FindName('Detalle').Text = $detalle; $w.FindName('Barra').Value = [math]::Max(0.0, [math]::Min(1.0, $fraccion)); $w.FindName('Cuenta').Text = $cuenta
    Bombear
}
function CerrarProgreso { if ($script:prog) { $script:cerrandoProgreso = $true; $script:prog.Close(); $script:prog = $null } }
function Bombear { [Windows.Forms.Application]::DoEvents() }

# robocopy en un proceso aparte, para que la ventana siga respondiendo y se pueda detener
function Robo([string[]]$argumentos) {
    $args2 = ($argumentos | ForEach-Object { if ($_ -match '[\s]' -and $_ -notmatch '^/') { "`"$_`"" } elseif ($_ -match '^(/LOG\+:)(.+)$') { "$($Matches[1])`"$($Matches[2])`"" } else { $_ } }) -join ' '
    $pi = New-Object Diagnostics.ProcessStartInfo 'robocopy.exe', $args2
    $pi.UseShellExecute = $false; $pi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($pi)
    while (-not $p.WaitForExit(150)) {
        Bombear
        if ($script:detener) { try { $p.Kill() } catch {}; $p.WaitForExit(); return 16 }
    }
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

foreach ($disco in $conectados) {
    if ($script:detener) { break }
    Add-Content $Log "===== DISCO $($disco.Nombre) ($($disco.Letra)) ====="
    Progreso "Copiando en «$($disco.Nombre)»" "Preparando el disco $($disco.Letra)..." 0
    New-Item -ItemType Directory -Path $disco.Raiz -Force | Out-Null

    # 3) Compresion (solo NTFS)
    if ($disco.Formato -eq "NTFS") { compact.exe /c /i /q "$($disco.Raiz)" | Out-Null }
    else { Add-Content $Log "Formato $($disco.Formato): sin compresion" }

    # 4) Reparto: asignar carpetas nuevas y quedarnos con las de este disco
    $rep = AsignarNuevas
    $unidades = @(UnidadesActuales | Where-Object { $rep[$_.Clave] -eq $disco.Id })

    # 5) Aviso de espacio previsto
    $tam = LeerTamUnidades
    $previsto = ($unidades | ForEach-Object { [int64]$tam[$_.Clave] } | Measure-Object -Sum).Sum
    if ($previsto -gt $disco.Capacidad) {
        $r = Aviso "«$($disco.Nombre)» se queda pequeño" "A este disco le corresponden $(GB $previsto), pero solo tiene $(GB $disco.Capacidad). Conviene añadir otro disco: lo nuevo irá al que tenga más sitio.`n`n¿Copiar igualmente lo que quepa?" @('No', 'Copiar igualmente') 'Copiar igualmente'
        if ($r -ne 'Copiar igualmente') { $resumen += "$($disco.Nombre): no se copió por falta de espacio"; continue }
    }

    # 6) Copia diferencial de cada unidad
    $errores = @(); $n = 0
    foreach ($u in $unidades) {
        if ($script:detener) { break }
        $n++
        Progreso $null "$($u.Carpeta.Origen | Split-Path -Leaf)  $([char]0x203A)  $($u.Nombre)" (($n - 1) / [math]::Max(1, $unidades.Count)) "$n de $($unidades.Count) carpetas"
        if ($u.Tipo -eq 'carpeta') {
            $dst = Join-Path $disco.Raiz (Join-Path $u.Carpeta.Destino $u.Nombre)
            $c = Robo (@($u.Clave, $dst, '/XD') + $Excluir + @('/MIR', '/FFT', '/XJ', '/R:1', '/W:2', '/MT:8', '/NP', '/NDL', "/LOG+:$Log"))
            if ($c -ge 8 -and -not $script:detener) { $errores += "$($u.Clave) (código $c)" }
        } else {
            # Archivos sueltos de la raiz: copiar solo los de primer nivel y borrar los que ya no existen
            $dst = Join-Path $disco.Raiz $u.Carpeta.Destino
            $c = Robo @($u.Carpeta.Origen, $dst, '/FFT', '/R:1', '/W:2', '/NP', '/NDL', "/LOG+:$Log")
            if ($c -ge 8 -and -not $script:detener) { $errores += "$($u.Carpeta.Origen)\* (código $c)" }
            Get-ChildItem -LiteralPath $dst -File -Force -ErrorAction SilentlyContinue |
                Where-Object { -not (Test-Path -LiteralPath (Join-Path $u.Carpeta.Origen $_.Name)) } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
    if ($script:detener) { $resumen += "$($disco.Nombre): copia detenida en la carpeta $n de $($unidades.Count). Lo copiado se conserva."; break }

    # 7) Espejo: borrar del disco las carpetas que ya no existen en el origen
    $actuales = @{}; UnidadesActuales | ForEach-Object { $actuales[$_.Clave] = $true }
    foreach ($k in @($rep.Keys)) {
        if ($rep[$k] -ne $disco.Id -or $actuales.ContainsKey($k) -or $k.EndsWith('\*')) { continue }
        $c = $Carpetas | Where-Object { DentroDe $k $_.Origen } | Select-Object -First 1
        if (-not $c -or -not (Test-Path -LiteralPath $c.Origen)) { continue }   # si el disco de origen no esta, no tocar nada
        $dst = Join-Path $disco.Raiz (Join-Path $c.Destino (Split-Path $k -Leaf))
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
                Backup  = Join-Path $disco.Raiz (Join-Path $u.Carpeta.Destino $u.Nombre)
                Archivo = Join-Path $disco.Raiz (Join-Path "_ARCHIVO" (Join-Path $u.Carpeta.Destino $u.Nombre))
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
    $errores = @(); $validos = @{}; $sueltos = @{}; $k = 0; $sel = @($plan.Seleccion)
    foreach ($u in $sel) {
        if ($script:detener) { break }
        $k++; Progreso $null "$($u.Carpeta.Origen | Split-Path -Leaf)  $([char]0x203A)  $($u.Nombre)" (($k - 1) / [math]::Max(1, $sel.Count)) "$k de $($sel.Count) carpetas"
        if ($directa) {
            # Nube directa: rclone sube (y cifra, si se eligio) sin pasar por ninguna carpeta del PC
            if ($u.Tipo -eq 'carpeta') { $validos[(RutaRemota $n (Join-Path $u.Carpeta.Destino $u.Nombre)).ToLower()] = $true } else { $sueltos[$u.Carpeta.Origen.ToLower()] = $true }
            $c = SubirUnidadRclone $u $n $Log
            if ($c -ne 0 -and -not $script:detener) { $errores += "$($u.Clave) (rclone, código $c)" }
            continue
        }
        if ($u.Tipo -eq 'carpeta') {
            $dst = Join-Path $ruta (Join-Path $u.Carpeta.Destino $u.Nombre); $validos[$dst.ToLower()] = $true
            $c = Robo (@($u.Clave, $dst, '/XD') + $Excluir + @('/MIR', '/FFT', '/XJ', '/R:1', '/W:2', '/MT:4', '/NP', '/NDL', "/LOG+:$Log"))
            if ($c -ge 8 -and -not $script:detener) { $errores += "$($u.Clave) (código $c)" }
        } else {
            $dst = Join-Path $ruta $u.Carpeta.Destino; $validos["$($dst.ToLower())|sueltos"] = $true
            $c = Robo @($u.Carpeta.Origen, $dst, '/FFT', '/R:1', '/W:2', '/NP', '/NDL', "/LOG+:$Log")
            if ($c -ge 8 -and -not $script:detener) { $errores += "$($u.Carpeta.Origen)\* (código $c)" }
            Get-ChildItem -LiteralPath $dst -File -Force -ErrorAction SilentlyContinue |
                Where-Object { -not (Test-Path -LiteralPath (Join-Path $u.Carpeta.Origen $_.Name)) } | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
    if ($script:detener) { $resumen += "Nube «$($n.Nombre)»: copia detenida. Lo copiado se conserva."; break }
    # Espejo, solo dentro de BackupApp: se quita lo que ya no toca subir (ya no cabe, se borro o cambio de prioridad)
    if ($directa) { EspejoRclone $n $validos $sueltos }
    else { foreach ($c in $Carpetas) {
        $base = Join-Path $ruta $c.Destino
        if (-not (Test-Path -LiteralPath $base)) { continue }
        Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue | Where-Object { -not $validos.ContainsKey($_.FullName.ToLower()) } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        if (-not $validos.ContainsKey("$($base.ToLower())|sueltos")) { Get-ChildItem -LiteralPath $base -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
    } }
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
