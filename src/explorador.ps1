# ============================================================
#  EXPLORAR DISCOS: el usuario recorre cualquier disco (los del PC y los de backup), ve que ocupa cada carpeta
#  y decide, independientemente del plan de copias:
#  - Copiar a un disco de backup y borrar del PC: se copia a <disco>\BACKUP\_ARCHIVO, se comprueba que la copia
#    es identica y solo entonces se borra del PC (lo hace backup_mensual.ps1 -Archivar, con ventana de progreso).
#  - Borrar: a la papelera o definitivamente, avisando si es algo del plan de copias o la unica copia archivada.
#  Los tamanos se miden en segundo plano (un solo medidor, como en el asistente).
# ============================================================
$GlifoArchivo = [string][char]0xE7C3; $GlifoSubir = [string][char]0xE74A
$NoMostrar = @('$Recycle.Bin', 'System Volume Information', '$WinREAgent', 'Recovery', 'Config.Msi', '$SysReset', '$Windows.~BT', '$Windows.~WS')

$XamlExplorador = @"
<Window $VentanaBase Title="Explorar discos" Width="1040" Height="780" MinWidth="760" MinHeight="520" WindowStartupLocation="CenterScreen">
  <Grid Margin="32,26,32,22">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Explorar discos" FontSize="28" FontWeight="SemiBold" FontFamily="Segoe UI Variable Display, Segoe UI"/>
    <TextBlock Grid.Row="1" Foreground="{DynamicResource Texto2}" Margin="0,6,0,14" TextWrapping="Wrap" Text="Mira qué ocupa cada carpeta y decide tú qué hacer con ella: copiarla a un disco de backup y borrarla del PC, o borrarla sin más. No depende del plan de copias."/>
    <WrapPanel x:Name="Unidades" Grid.Row="2" Margin="0,0,0,10"/>
    <DockPanel Grid.Row="3" Margin="0,0,0,10">
      <Button x:Name="BtnSubir" DockPanel.Dock="Left" Padding="12,6" Margin="0,0,10,0" ToolTip="Subir a la carpeta de arriba"/>
      <TextBlock x:Name="Ruta" VerticalAlignment="Center" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
    </DockPanel>
    <ScrollViewer x:Name="Scroll" Grid.Row="4" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0,0,10,0"><StackPanel x:Name="Lista"/></ScrollViewer>
    <Grid Grid.Row="5" Margin="0,16,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="Seleccion" VerticalAlignment="Center" FontWeight="SemiBold" TextWrapping="Wrap"/>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
        <Button x:Name="BtnCerrar" Content="Cerrar" Margin="0,0,8,0"/>
        <Button x:Name="BtnBorrar" Content="Borrar..." Margin="0,0,8,0" IsEnabled="False"/>
        <Button x:Name="BtnArchivar" Content="Copiar a un disco de backup y borrar del PC" Style="{DynamicResource Primario}" IsEnabled="False"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
"@

function MostrarExplorador($ruta = $null) {
    if ($script:exp -and (VentanaAbierta $script:exp.Win)) { MostrarSinBloquear $script:exp.Win; if ($ruta) { IrA $ruta }; return }
    $w = NuevaVentana $XamlExplorador
    $script:exp = @{ Win = $w; Ruta = $null; Filas = @(); Sel = @{}; Medidor = $null; Proc = $null
                     Cola = (New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]')
                     Estado = [hashtable]::Synchronized(@{ Gen = 0; Clave = $null; Contador = (New-Object 'long[]' 1); Tam = [hashtable]::Synchronized(@{}) }) }
    $w.FindName('BtnSubir').Content = (Icono $GlifoSubir 14)
    $w.FindName('BtnSubir').add_Click({ $p = Split-Path $script:exp.Ruta -Parent; if ($p) { IrA $p } })
    $w.FindName('BtnCerrar').add_Click({ $script:exp.Win.Close() })
    $w.FindName('BtnBorrar').add_Click({ BorrarSeleccionExp })
    $w.FindName('BtnArchivar').add_Click({ ArchivarSeleccionExp })
    $script:exp.Timer = New-Object Windows.Threading.DispatcherTimer; $script:exp.Timer.Interval = [TimeSpan]::FromMilliseconds(400)
    $script:exp.Timer.add_Tick({ TickExplorador })
    $w.add_Closed({ $e = $script:exp; $e.Timer.Stop(); $e.Estado.Gen++; if ($e.Medidor) { try { [void]$e.Medidor.PS.BeginStop($null, $null) } catch {} } })   # sin esperar: una medicion grande podia dejar el icono colgado
    PintarUnidadesExp
    MostrarSinBloquear $w
    $script:exp.Timer.Start()
    IrA $(if ($ruta) { $ruta } else { $env:SystemDrive + '\' })
}
function PintarUnidadesExp {
    $p = $script:exp.Win.FindName('Unidades'); $p.Children.Clear()
    $discos = @(DiscosConectados)
    foreach ($dr in @(UnidadesDeDisco)) {
        $l = $dr.Name.Substring(0, 2)
        $bk = $discos | Where-Object { $_.Letra -eq $l } | Select-Object -First 1
        $nombre = if ($bk) { "$l $($bk.Nombre) (backup)" } else { "$l $($dr.VolumeLabel)" }
        $b = New-Object Windows.Controls.Button; $b.Margin = '0,0,8,6'; $b.Padding = '12,6'; $b.Tag = $dr.RootDirectory.FullName
        $usado = ($dr.TotalSize - $dr.AvailableFreeSpace) / [math]::Max(1.0, [double]$dr.TotalSize)
        $barra = BarraUso $usado $(if ($dr.AvailableFreeSpace -lt 0.1 * $dr.TotalSize) { 'Aviso' } else { 'Acento' }); $barra.Width = 150; $barra.Margin = '0,5,0,0'
        $b.Content = Apilar @((Fila @((Icono $(if ($bk) { [string][char]0xE88E } else { $GlifoDiscoDuro }) 16 'Acento'), (Texto "$nombre   $(TamTxt $dr.AvailableFreeSpace) libres" 12.5 'SemiBold')) @('Auto', '*')), $barra)
        $b.Content.Children[0].Children[1].Margin = '8,0,0,0'
        $b.add_Click({ param($s, $e) IrA $s.Tag })
        [void]$p.Children.Add($b)
    }
}
function EstadoRuta($ruta) {
    # Que es esta ruta para BackupApp: parte del plan, copia de backup o archivo (unica copia)
    $r = $ruta.TrimEnd('\') + '\'
    foreach ($d in @(DiscosConectados)) {
        $raiz = $d.Raiz.TrimEnd('\') + '\'
        if ($r.StartsWith(($raiz + '_ARCHIVO\'), [StringComparison]::OrdinalIgnoreCase)) { return @('archivo', $d) }
        if ($r.StartsWith($raiz, [StringComparison]::OrdinalIgnoreCase)) { return @('backup', $d) }
        if ($r.Equals($d.Letra + '\', [StringComparison]::OrdinalIgnoreCase)) { return @('discobackup', $d) }
    }
    foreach ($c in $Carpetas) { if ((DentroDe $ruta $c.Origen) -or (DentroDe $c.Origen $ruta)) { return @('plan', $c) } }
    return @('', $null)
}
function IrA($ruta) {
    $e = $script:exp; $w = $e.Win
    if (-not (Test-Path -LiteralPath $ruta)) { return }
    $e.Ruta = $ruta; $e.Estado.Gen++; $e.Sel = @{}
    # Para saber que subcarpetas ya tienen copia en un disco conectado (se lee una vez por carpeta)
    $e.Discos = @(DiscosConectados); $e.Rep = LeerReparto; $e.Copias = @{}
    $w.FindName('Ruta').Text = $ruta
    $w.FindName('BtnSubir').IsEnabled = [bool](Split-Path $ruta -Parent)
    $lista = $w.FindName('Lista'); $lista.Children.Clear()
    $items = @(Get-ChildItem -LiteralPath $ruta -Force -ErrorAction SilentlyContinue |
               Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $NoMostrar -notcontains $_.Name })
    $e.Filas = @(foreach ($i in $items) {
        $dir = $i.PSIsContainer
        if (-not $dir) { $e.Estado.Tam[$i.FullName] = [int64]$i.Length }
        elseif (-not $e.Estado.Tam.ContainsKey($i.FullName)) { $e.Cola.Enqueue([pscustomobject]@{ Ruta = $i.FullName; Gen = $e.Estado.Gen }) }
        [pscustomobject]@{ Ruta = $i.FullName; Nombre = $i.Name; Dir = $dir; Fecha = $i.LastWriteTime; Check = $null; TxtTam = $null; Barra = $null; Card = $null }
    })
    if (-not $e.Filas) { [void]$lista.Children.Add((Tarjeta (Texto "Esta carpeta está vacía o no se puede leer." 13 'Normal' 'Texto2'))) }
    PintarFilasExp
    AsegurarMedidorExp
    ActualizarSeleccionExp
}
function PintarFilasExp {
    # Ordena por tamano (lo medido primero) y dibuja cada fila con una barra relativa a la mas grande
    $e = $script:exp; $lista = $e.Win.FindName('Lista'); $lista.Children.Clear()
    $e.Filas = @($e.Filas | Sort-Object { -[int64]$e.Estado.Tam[$_.Ruta] }, Nombre)
    $max = [double](($e.Filas | ForEach-Object { [int64]$e.Estado.Tam[$_.Ruta] } | Measure-Object -Maximum).Maximum)
    for ($k = 0; $k -lt $e.Filas.Count; $k++) {
        $f = $e.Filas[$k]
        $chk = New-Object Windows.Controls.CheckBox; $chk.Tag = $k; $chk.IsChecked = $e.Sel.ContainsKey($f.Ruta)
        $chk.add_Click({ param($s, $x) $f = $script:exp.Filas[$s.Tag]; if ($s.IsChecked) { $script:exp.Sel[$f.Ruta] = $f } else { $script:exp.Sel.Remove($f.Ruta) }; ActualizarSeleccionExp })
        $f.Check = $chk
        $ico = Icono $(if ($f.Dir) { [string][char]0xE8B7 } else { $GlifoArchivo }) 18 $(if ($f.Dir) { 'Acento' } else { 'Texto2' }); $ico.Margin = '12,0,10,0'
        if ($f.Dir) {
            $nom = New-Object Windows.Controls.Button; $nom.Style = $script:Estilos['Enlace']; $nom.Content = $f.Nombre; $nom.FontSize = 14; $nom.Tag = $f.Ruta
            $nom.add_Click({ param($s, $x) IrA $s.Tag }); $nom.HorizontalAlignment = 'Left'
        } else { $nom = Texto $f.Nombre 14 }
        $est = EstadoRuta $f.Ruta
        $chips = New-Object Windows.Controls.WrapPanel
        switch ($est[0]) {
            'plan'    {
                if ($f.Dir -and -not $e.Copias.ContainsKey($f.Ruta)) { $e.Copias[$f.Ruta] = CopiaEnDisco $f.Ruta $e.Discos $e.Rep }
                $cp = $e.Copias[$f.Ruta]
                if ($cp) { [void]$chips.Children.Add((Chip "Copiada en «$($cp.Disco.Nombre)»" 'acento')) } else { [void]$chips.Children.Add((Chip "En tu plan de copias" 'normal')) }
            }
            'backup'  { [void]$chips.Children.Add((Chip "Copia de backup" 'normal')) }
            'archivo' { [void]$chips.Children.Add((Chip "Archivado: es la única copia" 'aviso')) }
        }
        $info = Apilar @($nom, (Texto "$(if ($f.Dir) { 'Carpeta' } else { 'Archivo' })  $([char]0x00B7)  modificado el $($f.Fecha.ToString('dd/MM/yyyy'))" 11.5 'Normal' 'Texto2'), $chips)
        $tam = [int64]$e.Estado.Tam[$f.Ruta]; $medido = $e.Estado.Tam.ContainsKey($f.Ruta)
        $txt = Texto $(if ($medido) { TamTxt $tam } else { "midiendo..." }) 14 'SemiBold' $(if ($medido) { 'Texto' } else { 'Texto2' }); $txt.TextWrapping = 'NoWrap'; $txt.HorizontalAlignment = 'Right'
        $barra = BarraUso $(if ($max -gt 0) { $tam / $max } else { 0 }); $barra.Margin = '0,6,0,0'
        $der = Apilar @($txt, $barra); $der.Width = 170; $der.Margin = '12,0,0,0'
        $f.TxtTam = $txt
        $card = Tarjeta (Fila @($chk, $ico, $info, $der) @('Auto', 'Auto', '*', 'Auto')); $card.Padding = '14,8'; $card.Margin = '0,0,0,6'
        $f.Card = $card
        [void]$lista.Children.Add($card)
    }
}
function AsegurarMedidorExp {
    $e = $script:exp
    if ($e.Medidor -and -not $e.Medidor.H.IsCompleted) { return }
    if ($e.Cola.IsEmpty) { $e.Estado.Clave = $null; return }
    if ($e.Medidor) { try { $e.Medidor.PS.Dispose() } catch {} }
    $ps = [powershell]::Create()
    [void]$ps.AddScript({
        param($config, $cola, $estado)
        . $config
        $u = $null; $cont = $estado.Contador
        while ($cola.TryDequeue([ref]$u)) {
            if ($u.Gen -ne $estado.Gen -or $estado.Tam.ContainsKey($u.Ruta)) { continue }   # ya no se ve esa carpeta o ya esta medida
            $cont[0] = 0; $estado.Clave = $u.Ruta
            try { $m = Analizar $u.Ruta -Contador $cont; $estado.Tam[$u.Ruta] = [int64]$m.Bytes } catch { $estado.Tam[$u.Ruta] = [int64]0 }
        }
        $estado.Clave = $null
    }.ToString())
    foreach ($x in @((Join-Path $Codigo "config.ps1"), $e.Cola, $e.Estado)) { [void]$ps.AddArgument($x) }
    $e.Medidor = @{ PS = $ps; H = $ps.BeginInvoke() }
}
function TickExplorador {
    $e = $script:exp; if (-not $e.Filas) { AsegurarMedidorExp; return }
    $pend = 0; $cambio = $false
    foreach ($f in $e.Filas) {
        if ($e.Estado.Tam.ContainsKey($f.Ruta)) { if ($f.TxtTam.Text -eq 'midiendo...' -or $f.TxtTam.Text -like '*contados*') { $cambio = $true } }
        else {
            $pend++
            if ($e.Estado.Clave -eq $f.Ruta) { $f.TxtTam.Text = "$(TamTxt ([int64]$e.Estado.Contador[0])) contados" }
        }
    }
    # Al terminar de medir lo que se ve, se reordena por tamano (una vez, para no mover la lista mientras se marca)
    if ($cambio -and $pend -eq 0) { $sv = $e.Win.FindName('Scroll'); $pos = $sv.VerticalOffset; PintarFilasExp; $sv.ScrollToVerticalOffset($pos) }
    elseif ($cambio) { foreach ($f in $e.Filas) { if ($e.Estado.Tam.ContainsKey($f.Ruta)) { $f.TxtTam.Text = TamTxt ([int64]$e.Estado.Tam[$f.Ruta]); $f.TxtTam.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Texto') } } }
    if ($cambio) { ActualizarSeleccionExp }
    AsegurarMedidorExp
    # Al terminar un archivado o un borrado, se vuelve a leer la carpeta
    if ($e.Proc -and $e.Proc.HasExited) { $e.Proc = $null; foreach ($k in @($e.Estado.Tam.Keys)) { if (-not (Test-Path -LiteralPath $k)) { $e.Estado.Tam.Remove($k) } }; PintarUnidadesExp; IrA $e.Ruta }
}
function ActualizarSeleccionExp {
    $e = $script:exp; $w = $e.Win
    $sel = @($e.Sel.Values); $bytes = [int64](($sel | ForEach-Object { [int64]$e.Estado.Tam[$_.Ruta] } | Measure-Object -Sum).Sum)
    $sinMedir = @($sel | Where-Object { -not $e.Estado.Tam.ContainsKey($_.Ruta) }).Count
    $w.FindName('Seleccion').Text = if ($sel) { "$($sel.Count) seleccionados  $([char]0x00B7)  $(TamTxt $bytes)$(if ($sinMedir) { ' (midiendo...)' })" } else { "Marca las carpetas o archivos que quieras copiar y borrar, o solo borrar." }
    $w.FindName('BtnBorrar').IsEnabled = [bool]$sel
    $enBackup = @($sel | Where-Object { (EstadoRuta $_.Ruta)[0] -in 'backup', 'archivo', 'discobackup' })
    $w.FindName('BtnArchivar').IsEnabled = [bool]$sel -and -not $enBackup -and -not $sinMedir -and -not $e.Proc
    # Si todo lo marcado ya esta copiado, no hace falta volver a copiarlo: solo se comprueba y se borra del PC
    $copiadas = @($sel | Where-Object { $e.Copias -and $e.Copias[$_.Ruta] })
    $w.FindName('BtnArchivar').Content = if ($sel -and $copiadas.Count -eq $sel.Count) { "Borrar del PC (ya están copiadas)" } else { "Copiar a un disco de backup y borrar del PC" }
}

# ---------- Copiar a un disco de backup y borrar del PC ----------
function ArchivarSeleccionExp {
    $e = $script:exp; $w = $e.Win
    $sel = @($e.Sel.Values); $bytes = [int64](($sel | ForEach-Object { [int64]$e.Estado.Tam[$_.Ruta] } | Measure-Object -Sum).Sum)
    if ((Get-Command Copiando -ErrorAction SilentlyContinue) -and (Copiando)) { [void](Dialogo $w "Hay una copia en marcha" "Espera a que termine la copia de seguridad."); return }
    $letras = @($sel | ForEach-Object { $_.Ruta.Substring(0, 2).ToUpper() } | Select-Object -Unique)
    $discos = @(DiscosConectados | Where-Object { $letras -notcontains $_.Letra.ToUpper() })
    if (-not $discos) { [void](Dialogo $w "Conecta un disco de backup" "Para copiar y borrar hace falta un disco de backup conectado (distinto del disco donde están estas carpetas)."); return }
    # Lo que ya tiene copia va a su disco: no se vuelve a copiar, solo se comprueba y se aparta en _ARCHIVO
    $conCopia = @($sel | Where-Object { $e.Copias[$_.Ruta] })
    $discosCopia = @($conCopia | ForEach-Object { $e.Copias[$_.Ruta].Disco.Id } | Select-Object -Unique)
    if ($discosCopia.Count -gt 1) { [void](Dialogo $w "Están en discos distintos" "Lo que has marcado está copiado en varios discos de backup. Márcalo por separado, un disco cada vez."); return }
    $d = $discos[0]
    if ($discosCopia.Count -eq 1) { $d = $discos | Where-Object { $_.Id -eq $discosCopia[0] } | Select-Object -First 1 }
    elseif ($discos.Count -gt 1) {
        $r = Dialogo $w "¿A qué disco?" "Elige el disco de backup donde se guardarán:" (@('Cancelar') + @($discos | ForEach-Object { "$($_.Nombre) ($(TamTxt ([int64]$_.Libre)) libres)" }))
        $d = $discos | Where-Object { $r -like "$($_.Nombre) (*" } | Select-Object -First 1
        if (-not $d) { return }
    }
    $nuevos = [int64](($sel | Where-Object { -not $e.Copias[$_.Ruta] } | ForEach-Object { [int64]$e.Estado.Tam[$_.Ruta] } | Measure-Object -Sum).Sum)
    if ([int64]$d.Libre -lt $nuevos * 1.02) { [void](Dialogo $w "No cabe" "Hay que copiar $(TamTxt $nuevos), pero en «$($d.Nombre)» solo quedan $(TamTxt ([int64]$d.Libre)) libres."); return }
    $plan = @($sel | Where-Object { (EstadoRuta $_.Ruta)[0] -eq 'plan' })
    $msg = $(if ($conCopia.Count -eq $sel.Count) { "Ya están copiadas en «$($d.Nombre)». Se comprobará que su copia es idéntica (si ha cambiado algo, se actualiza), se guardará aparte en $($d.Letra)\$CarpetaBackup\_ARCHIVO para que la próxima copia no la quite, y después se borrarán de tu PC. Ganas $(TamTxt $bytes).`n`n" }
             else { "Se copiarán a «$($d.Nombre)» ($($d.Letra)\$CarpetaBackup\_ARCHIVO), se comprobará que la copia es idéntica y después se borrarán de tu PC. Ganas $(TamTxt $bytes).`n`n" }) +
           (($sel | Select-Object -First 12 | ForEach-Object { "$([char]0x2022) $($_.Ruta)" }) -join "`n") + $(if ($sel.Count -gt 12) { "`n... y $($sel.Count - 12) más" } else { "" }) +
           "`n`nDespués solo estarán en ese disco: guárdalo bien."
    if ($plan) { $msg += "`n`nAlgunas están en tu plan de copias: dejarán de copiarse porque ya no estarán en el PC." }
    if ((Dialogo $w "¿Copiar y borrar del PC?" $msg @('Cancelar', 'Copiar y borrar') 'Copiar y borrar') -ne 'Copiar y borrar') { return }
    $lista = Join-Path $Datos "archivar.json"
    [pscustomobject]@{ Disco = $d.Id; Items = @($sel | ForEach-Object { [pscustomobject]@{ Ruta = $_.Ruta; Bytes = [int64]$e.Estado.Tam[$_.Ruta]; Copia = $(if ($e.Copias[$_.Ruta]) { $e.Copias[$_.Ruta].Ruta } else { '' }) } }) } | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $lista -Encoding UTF8
    $e.Proc = Start-Process powershell.exe -PassThru -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$(Join-Path $Codigo 'backup_mensual.ps1')`" -Archivar `"$lista`""
    $e.Sel = @{}; foreach ($f in $e.Filas) { $f.Check.IsChecked = $false }; ActualizarSeleccionExp
}

# ---------- Borrar ----------
function BorrarSeleccionExp {
    $e = $script:exp; $w = $e.Win
    $sel = @($e.Sel.Values); $bytes = [int64](($sel | ForEach-Object { [int64]$e.Estado.Tam[$_.Ruta] } | Measure-Object -Sum).Sum)
    $archivo = @($sel | Where-Object { (EstadoRuta $_.Ruta)[0] -eq 'archivo' })
    $plan = @($sel | Where-Object { (EstadoRuta $_.Ruta)[0] -eq 'plan' })
    $backup = @($sel | Where-Object { (EstadoRuta $_.Ruta)[0] -in 'backup', 'discobackup' })
    $msg = "Vas a borrar $($sel.Count) elementos ($(TamTxt $bytes)):`n`n" + (($sel | Select-Object -First 12 | ForEach-Object { "$([char]0x2022) $($_.Ruta)" }) -join "`n") + $(if ($sel.Count -gt 12) { "`n... y $($sel.Count - 12) más" } else { "" })
    if ($archivo) { $msg += "`n`nATENCIÓN: $($archivo.Count) están en _ARCHIVO. Es la única copia que queda: si los borras, se pierden para siempre." }
    if ($backup) { $msg += "`n`n$($backup.Count) son copias de tu plan de copias: si lo que copian sigue en tu PC, se volverán a copiar en la próxima copia." }
    if ($plan) { $msg += "`n`n$($plan.Count) están en tu plan de copias: su copia en el disco de backup se quitará en la próxima copia. Si quieres conservarla, usa «Copiar a un disco de backup y borrar del PC»." }
    $msg += "`n`nEn la papelera puedes recuperarlos, pero el espacio no se libera hasta que la vacíes."
    $r = Dialogo $w "¿Borrar?" $msg @('Cancelar', 'Borrar definitivamente', 'A la papelera') 'A la papelera'
    if ($r -notin 'Borrar definitivamente', 'A la papelera') { return }
    if ($archivo -and $r -eq 'Borrar definitivamente' -and (Dialogo $w "Última comprobación" "Lo archivado en _ARCHIVO no tiene otra copia. ¿Seguro que quieres borrarlo para siempre?" @('No', 'Sí, borrar') 'No') -ne 'Sí, borrar') { return }
    # El borrado va en otro proceso para que la ventana no se congele con carpetas grandes
    $rutas = Join-Path $Datos "borrar.txt"; [IO.File]::WriteAllLines($rutas, [string[]]@($sel | ForEach-Object { $_.Ruta }))
    $script = Join-Path $Datos "borrar.ps1"
    [IO.File]::WriteAllText($script, @'
param($lista, [switch]$Papelera)
Add-Type -AssemblyName Microsoft.VisualBasic
foreach ($r in [IO.File]::ReadAllLines($lista)) {
    try {
        if ($Papelera) {
            if (Test-Path -LiteralPath $r -PathType Container) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($r, 'OnlyErrorDialogs', 'SendToRecycleBin') }
            else { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($r, 'OnlyErrorDialogs', 'SendToRecycleBin') }
        } else { Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction Stop }
    } catch {}
}
Remove-Item -LiteralPath $lista -Force
'@, (New-Object Text.UTF8Encoding $true))
    $e.Proc = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$script`" -lista `"$rutas`"$(if ($r -eq 'A la papelera') { ' -Papelera' })"
    $e.Sel = @{}; foreach ($f in $e.Filas) { $f.Check.IsChecked = $false }
    $w.FindName('Seleccion').Text = "Borrando..."
    ActualizarSeleccionExp
}
