# ============================================================
#  EDITAR EL PLAN: el usuario decide que se copia y a que disco, subcarpeta a subcarpeta
#  - Casilla: incluir o quitar una subcarpeta (excluidas.txt; su copia en el disco no se borra)
#  - "Elegir dentro": abre una subcarpeta para escoger sus subcarpetas (divididas.txt), a cualquier profundidad
#  - Disco: "Automatico" (lo decide Repartir) o un disco concreto (fijo en reparto.csv)
#  - Arriba, cada disco con lo que le toca; se recalcula con cada cambio.
#  Nada se guarda hasta pulsar "Guardar plan".
# ============================================================
$XamlEditor = @"
<Window $VentanaBase Title="Editar el plan de copias" Width="1080" Height="800" MinWidth="820" MinHeight="560" WindowStartupLocation="CenterScreen">
  <Grid Margin="32,26,32,22">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Editar el plan de copias" FontSize="28" FontWeight="SemiBold" FontFamily="Segoe UI Variable Display, Segoe UI"/>
    <TextBlock Grid.Row="1" Foreground="{DynamicResource Texto2}" Margin="0,6,0,14" TextWrapping="Wrap" Text="Marca exactamente qué quieres copiar y a qué disco. «Elegir dentro» abre una carpeta para escoger sus subcarpetas una a una. Lo que quites del plan no se borra del disco: solo deja de actualizarse."/>
    <UniformGrid x:Name="Discos" Grid.Row="2" Rows="1" Margin="0,0,0,12"/>
    <ScrollViewer x:Name="Scroll" Grid.Row="3" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0,0,10,0"><StackPanel x:Name="Lista"/></ScrollViewer>
    <Grid Grid.Row="4" Margin="0,16,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Button x:Name="BtnAnadir" Content="+  Añadir carpeta"/>
      <TextBlock x:Name="Estado" Grid.Column="1" Margin="16,0,16,0" VerticalAlignment="Center" Foreground="{DynamicResource Texto2}" TextWrapping="Wrap"/>
      <StackPanel Grid.Column="2" Orientation="Horizontal">
        <Button x:Name="BtnCancelar" Content="Cancelar" Margin="0,0,8,0"/>
        <Button x:Name="BtnGuardar" Content="Guardar plan" Style="{DynamicResource Primario}" MinWidth="140"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
"@

function MostrarEditorPlan($alGuardar = $null) {
    if ($script:ed -and $script:ed.Win -and $script:ed.Win.IsVisible) { [void]$script:ed.Win.Activate(); return }
    $w = NuevaVentana $XamlEditor
    $car = New-Object 'System.Collections.Generic.List[object]'
    foreach ($c in @(LeerCarpetas)) { $car.Add([pscustomobject]@{ Origen = $c.Origen; Destino = $c.Destino; Prioridad = $c.Prioridad }) }
    $rep = @{}; $r0 = LeerReparto; foreach ($k in $r0.Keys) { if ($r0[$k] -ne $EnEspera) { $rep[$k] = $r0[$k] } }
    $script:ed = @{ Win = $w; Carpetas = $car; Div = (LeerLista $FicheroDivididas); Exc = (LeerLista $FicheroExcluidas); Rep = $rep
                    Tam = (LeerTamUnidades); Discos = @(LeerDiscos); AlGuardar = $alGuardar; Proy = @{}; Cambios = $false }
    $w.FindName('BtnAnadir').add_Click({ AnadirCarpetaEd })
    $w.FindName('BtnCancelar').add_Click({ $script:ed.Win.Close() })
    $w.FindName('BtnGuardar').add_Click({ GuardarEditorPlan })
    $w.add_Closing({ param($s, $e)
        if ($script:ed.Cambios -and -not $script:ed.Guardado -and (Dialogo $script:ed.Win "¿Salir sin guardar?" "Has hecho cambios en el plan que todavía no están guardados." @('Seguir editando', 'Salir sin guardar') 'Seguir editando') -ne 'Salir sin guardar') { $e.Cancel = $true }
    })
    MostrarSinBloquear $w
    $w.Cursor = [Windows.Input.Cursors]::Wait
    MedirFaltanEd
    PintarEditor
    $w.Cursor = $null
}
function UnidadesEd { @(UnidadesDe $script:ed.Carpetas.ToArray() $script:ed.Div $script:ed.Exc) }
function MedirFaltanEd {
    # Las subcarpetas que aun no se han medido se miden ahora (rapido: sin node_modules ni caches)
    $ed = $script:ed; $faltan = @(UnidadesDe $ed.Carpetas.ToArray() $ed.Div $ed.Exc -ConExcluidas | Where-Object { -not $ed.Tam.ContainsKey($_.Clave) })
    $i = 0
    foreach ($u in $faltan) {
        $i++; $ed.Win.FindName('Estado').Text = "Midiendo $i de $($faltan.Count): $($u.Rel)"; [Windows.Forms.Application]::DoEvents()
        try { $a = if ($u.Tipo -eq 'sueltos') { Analizar $u.Dir -SoloRaiz } else { Analizar $u.Clave -Rapido }; $ed.Tam[$u.Clave] = [int64]$a.BytesBackup } catch { $ed.Tam[$u.Clave] = [int64]0 }
    }
}
function NombreDisco($id) { ($script:ed.Discos | Where-Object { $_.Id -eq $id } | Select-Object -First 1).Nombre }
function PintarEditor {
    $ed = $script:ed; $w = $ed.Win
    $sv = $w.FindName('Scroll'); $pos = $sv.VerticalOffset
    # Proyeccion: lo "automatico" se reparte como lo haria la copia
    $units = UnidadesEd
    $ed.Proy = Repartir $units $ed.Tam $ed.Discos ($ed.Rep.Clone())
    # Discos
    $dp = $w.FindName('Discos'); $dp.Children.Clear()
    foreach ($d in $ed.Discos) {
        $asig = [int64](($units | Where-Object { $ed.Proy[$_.Clave] -eq $d.Id } | ForEach-Object { [int64]$ed.Tam[$_.Clave] } | Measure-Object -Sum).Sum)
        $util = [math]::Max([int64]1, (EspacioUtil $d)); $pasa = $asig -gt $util
        $t = Tarjeta (Apilar @((Texto $d.Nombre 14 'SemiBold'), (BarraUso ($asig / [double]$util) $(if ($pasa) { 'Aviso' } else { 'Acento' })),
                               (Texto $(if ($pasa) { "$(TamTxt $asig) de $(TamTxt $util): se pasa $(TamTxt ($asig - $util))" } else { "$(TamTxt $asig) de $(TamTxt $util) $([char]0x00B7) quedan $(TamTxt ($util - $asig))" }) 12 'Normal' $(if ($pasa) { 'Aviso' } else { 'Texto2' }))))
        $t.Child.Children[1].Margin = '0,8,0,6'; $t.Margin = '0,0,8,0'
        [void]$dp.Children.Add($t)
    }
    $espera = [int64](($units | Where-Object { $ed.Proy[$_.Clave] -eq $EnEspera } | ForEach-Object { [int64]$ed.Tam[$_.Clave] } | Measure-Object -Sum).Sum)
    $t = Tarjeta (Apilar @((Texto "Sin sitio todavía" 14 'SemiBold'), (Texto (TamTxt $espera) 20 'SemiBold' $(if ($espera) { 'Aviso' } else { 'Texto2' })), (Texto "Lo automático que no cabe espera a otro disco" 12 'Normal' 'Texto2')))
    [void]$dp.Children.Add($t)
    $dp.Columns = $ed.Discos.Count + 1
    # Carpetas
    $l = $w.FindName('Lista'); $l.Children.Clear()
    for ($ci = 0; $ci -lt $ed.Carpetas.Count; $ci++) {
        $c = $ed.Carpetas[$ci]
        $pri = New-Object Windows.Controls.StackPanel; $pri.Orientation = 'Horizontal'
        foreach ($p in 1, 2, 3) {
            $rb = New-Object Windows.Controls.RadioButton; $rb.Style = $script:Estilos['Pastilla']; $rb.Content = $TextoPrioridad[$p]; $rb.GroupName = "edpri_$ci"
            $rb.IsChecked = ($c.Prioridad -eq $p); $rb.Tag = "$ci|$p"
            $rb.add_Checked({ param($s, $e) $i, $p = $s.Tag.Split('|'); $script:ed.Carpetas[[int]$i].Prioridad = [int]$p; $script:ed.Cambios = $true; PintarEditor })
            [void]$pri.Children.Add($rb)
        }
        $quitar = New-Object Windows.Controls.Button; $quitar.Style = $script:Estilos['Enlace']; $quitar.Content = "Quitar del plan"; $quitar.Tag = $ci; $quitar.Margin = '14,0,0,0'
        $quitar.add_Click({ param($s, $e) QuitarCarpetaEd $s.Tag })
        $cab = Fila @((Icono ([string][char]0xE8B7) 20 'Acento'), (Apilar @((Texto (Split-Path $c.Origen -Leaf) 16 'SemiBold'), (Texto $c.Origen 11.5 'Normal' 'Texto2'))), $pri, $quitar) @('Auto', '*', 'Auto', 'Auto')
        $cab.Children[1].Margin = '12,0,12,0'
        $filas = New-Object Windows.Controls.StackPanel; $filas.Margin = '0,10,0,0'
        if (Test-Path -LiteralPath $c.Origen) { PintarDirEd $c $c.Origen.TrimEnd('\') 0 $filas } else { [void]$filas.Children.Add((Texto "No se encuentra esta carpeta (¿disco desconectado?)." 12 'Normal' 'Aviso')) }
        [void]$l.Children.Add((Tarjeta (Apilar @($cab, $filas))))
    }
    if (-not $ed.Carpetas.Count) { [void]$l.Children.Add((Tarjeta (Texto "El plan está vacío. Pulsa «Añadir carpeta»." 13 'Normal' 'Texto2'))) }
    $incl = @($units).Count; $tot = [int64](($units | ForEach-Object { [int64]$ed.Tam[$_.Clave] } | Measure-Object -Sum).Sum)
    $w.FindName('Estado').Text = "$incl subcarpetas en el plan $([char]0x00B7) $(TamTxt $tot)$(if ($ed.Cambios) { "   $([char]0x00B7)   cambios sin guardar" })"
    $w.UpdateLayout(); $sv.ScrollToVerticalOffset($pos)
}
function PintarDirEd($c, $dir, $nivel, $panel) {
    # Una fila por subcarpeta: las "abiertas" muestran sus subcarpetas debajo, con sangria
    $ed = $script:ed
    foreach ($d in @(Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue |
                     Where-Object { ($Excluir -notcontains $_.Name) -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | Sort-Object Name)) {
        $p = $d.FullName
        if ($ed.Div.ContainsKey($p)) {
            $unir = New-Object Windows.Controls.Button; $unir.Style = $script:Estilos['Enlace']; $unir.Content = "Volver a copiarla entera"; $unir.Tag = $p
            $unir.add_Click({ param($s, $e) UnirEd $s.Tag })
            $f = Fila @((Icono ([string][char]0xE838) 15 'Texto2'), (Texto "$($d.Name)  (eliges dentro)" 13 'SemiBold'), $unir) @('Auto', '*', 'Auto')
            $f.Children[1].Margin = '8,0,0,0'; $f.Margin = "$(28 * $nivel),6,0,4"
            [void]$panel.Children.Add($f)
            PintarDirEd $c $p ($nivel + 1) $panel
        } else { [void]$panel.Children.Add((FilaUnidadEd $c $p $d.Name 'carpeta' $nivel)) }
    }
    if (Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1) {
        [void]$panel.Children.Add((FilaUnidadEd $c "$dir\*" "(archivos sueltos)" 'sueltos' $nivel))
    }
}
function FilaUnidadEd($c, $clave, $nombre, $tipo, $nivel) {
    $ed = $script:ed; $incluida = -not $ed.Exc.ContainsKey($clave)
    $chk = New-Object Windows.Controls.CheckBox; $chk.IsChecked = $incluida; $chk.Tag = $clave
    $chk.add_Click({ param($s, $e) if ($s.IsChecked) { $script:ed.Exc.Remove($s.Tag) } else { $script:ed.Exc[$s.Tag] = $true }; $script:ed.Cambios = $true; PintarEditor })
    $nom = Texto $nombre 13 $(if ($tipo -eq 'carpeta') { 'SemiBold' } else { 'Normal' }) $(if ($incluida) { 'Texto' } else { 'Texto2' }); $nom.Margin = '10,0,0,0'
    $dentro = $null
    if ($tipo -eq 'carpeta' -and (Get-ChildItem -LiteralPath $clave -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        $dentro = New-Object Windows.Controls.Button; $dentro.Style = $script:Estilos['Enlace']; $dentro.Content = "Elegir dentro"; $dentro.Tag = $clave; $dentro.Margin = '12,0,0,0'
        $dentro.add_Click({ param($s, $e) DividirEd $s.Tag })
    }
    $tam = Texto $(if ($ed.Tam.ContainsKey($clave)) { TamTxt ([int64]$ed.Tam[$clave]) } else { "—" }) 13 'SemiBold' $(if ($incluida) { 'Texto' } else { 'Texto2' })
    $tam.TextWrapping = 'NoWrap'; $tam.Margin = '12,0,12,0'
    $disco = $null
    if ($incluida) {
        $fijo = $ed.Rep[$clave]
        $txt = if ($fijo) { "$([char]0x2192) $(NombreDisco $fijo)" } elseif ($ed.Proy[$clave] -eq $EnEspera) { "Automático (no cabe: espera)" } else { "Automático $([char]0x2192) $(NombreDisco $ed.Proy[$clave])" }
        $disco = New-Object Windows.Controls.Button; $disco.Content = $txt; $disco.Tag = $clave; $disco.Padding = '10,4'; $disco.MinWidth = 210; $disco.FontSize = 12
        $disco.ToolTip = "Pulsa para cambiar: Automático $(($ed.Discos | ForEach-Object { "$([char]0x2192) $($_.Nombre)" }) -join ' ')"
        if ($fijo) { $disco.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'AcentoSuave') }
        $disco.add_Click({ param($s, $e) CambiarDiscoEd $s.Tag })
    } else { $disco = Texto "No se copia" 12 'Normal' 'Texto2'; $disco.MinWidth = 210; $disco.TextAlignment = 'Center' }
    $f = Fila @($chk, $nom, $dentro, $tam, $disco) @('Auto', '*', 'Auto', 'Auto', 'Auto')
    $f.Margin = "$(28 * $nivel),3,0,3"
    if (-not $incluida) { $f.Opacity = 0.75 }
    return $f
}
function CambiarDiscoEd($clave) {
    # Automatico -> disco 1 -> disco 2 -> ... -> Automatico
    $ed = $script:ed; $ids = @($ed.Discos | ForEach-Object { $_.Id })
    $actual = $ed.Rep[$clave]; $i = if ($actual) { [array]::IndexOf($ids, $actual) } else { -1 }
    if ($i + 1 -lt $ids.Count) { $ed.Rep[$clave] = $ids[$i + 1] } else { $ed.Rep.Remove($clave) }
    $ed.Cambios = $true; PintarEditor
}
function DividirEd($p) {
    # Las subcarpetas heredan lo que tenia la carpeta: su disco y si estaba quitada del plan
    $ed = $script:ed; $w = $ed.Win
    $ed.Div[$p] = $true
    $hijos = @(Get-ChildItem -LiteralPath $p -Directory -Force -ErrorAction SilentlyContinue | Where-Object { ($Excluir -notcontains $_.Name) -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | ForEach-Object { $_.FullName })
    if (Get-ChildItem -LiteralPath $p -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1) { $hijos += "$p\*" }
    foreach ($h in $hijos) {
        if ($ed.Rep[$p]) { $ed.Rep[$h] = $ed.Rep[$p] }
        if ($ed.Exc.ContainsKey($p)) { $ed.Exc[$h] = $true }
    }
    $ed.Rep.Remove($p); $ed.Exc.Remove($p)
    $w.Cursor = [Windows.Input.Cursors]::Wait; MedirFaltanEd; $w.Cursor = $null
    $ed.Cambios = $true; PintarEditor
}
function UnirEd($p) {
    # Vuelve a copiar la carpeta entera: se olvidan las decisiones de dentro; si todas iban al mismo disco, se mantiene
    $ed = $script:ed
    $pre = $p.TrimEnd('\') + '\'
    $discos = @($ed.Rep.Keys | Where-Object { $_.StartsWith($pre, [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { $ed.Rep[$_] } | Select-Object -Unique)
    foreach ($h in @($ed.Div.Keys)) { if ($h.StartsWith($pre, [StringComparison]::OrdinalIgnoreCase) -or $h -eq $p) { $ed.Div.Remove($h) } }
    foreach ($h in @($ed.Rep.Keys)) { if ($h.StartsWith($pre, [StringComparison]::OrdinalIgnoreCase)) { $ed.Rep.Remove($h) } }
    foreach ($h in @($ed.Exc.Keys)) { if ($h.StartsWith($pre, [StringComparison]::OrdinalIgnoreCase)) { $ed.Exc.Remove($h) } }
    if ($discos.Count -eq 1) { $ed.Rep[$p] = $discos[0] }
    $ed.Win.Cursor = [Windows.Input.Cursors]::Wait; MedirFaltanEd; $ed.Win.Cursor = $null
    $ed.Cambios = $true; PintarEditor
}
function QuitarCarpetaEd($i) {
    $ed = $script:ed; $c = $ed.Carpetas[[int]$i]
    if ((Dialogo $ed.Win "¿Quitar «$(Split-Path $c.Origen -Leaf)» del plan?" "Dejará de copiarse. Lo que ya está copiado en los discos no se borra." @('Cancelar', 'Quitar') 'Quitar') -ne 'Quitar') { return }
    $pre = $c.Origen.TrimEnd('\') + '\'
    foreach ($h in @($ed.Div.Keys) + @($ed.Rep.Keys) + @($ed.Exc.Keys)) { if ($h.StartsWith($pre, [StringComparison]::OrdinalIgnoreCase)) { $ed.Div.Remove($h); $ed.Rep.Remove($h); $ed.Exc.Remove($h) } }
    $ed.Carpetas.RemoveAt([int]$i); $ed.Cambios = $true; PintarEditor
}
function AnadirCarpetaEd {
    $ed = $script:ed
    $r = ElegirCarpeta $ed.Win "Elige una carpeta para añadir al plan"
    if (-not $r) { return }
    $r = $r.TrimEnd('\')
    if ($r -match '^[A-Za-z]:$') { [void](Dialogo $ed.Win "Elige una carpeta" "No se puede añadir una unidad entera."); return }
    foreach ($c in $ed.Carpetas) {
        if (DentroDe $r $c.Origen) { [void](Dialogo $ed.Win "Ya está en el plan" "Está dentro de «$($c.Origen)». Usa «Elegir dentro» en esa carpeta para escoger sus subcarpetas."); return }
        if (DentroDe $c.Origen $r) { [void](Dialogo $ed.Win "Contiene otra carpeta del plan" "Contiene «$($c.Origen)». Quita primero esa del plan."); return }
    }
    if (Test-Path -LiteralPath (Join-Path $r.Substring(0, 3) "$CarpetaBackup\$MarcaDisco")) { [void](Dialogo $ed.Win "Es un disco de backup" "Esa carpeta está en un disco de backup."); return }
    $ed.Carpetas.Add([pscustomobject]@{ Origen = $r; Destino = (DestinoDe $r); Prioridad = (PrioridadSugerida $r) })
    $ed.Win.Cursor = [Windows.Input.Cursors]::Wait; MedirFaltanEd; $ed.Win.Cursor = $null
    $ed.Cambios = $true; PintarEditor
}
function GuardarEditorPlan {
    $ed = $script:ed
    $units = UnidadesEd
    $txt = "Se guardará el plan con $(@($units).Count) subcarpetas.`n"
    foreach ($d in $ed.Discos) {
        $asig = [int64](($units | Where-Object { $ed.Proy[$_.Clave] -eq $d.Id } | ForEach-Object { [int64]$ed.Tam[$_.Clave] } | Measure-Object -Sum).Sum)
        $txt += "`n$([char]0x2022) «$($d.Nombre)»: $(TamTxt $asig) de $(TamTxt (EspacioUtil $d))$(if ($asig -gt (EspacioUtil $d)) { ' (no cabe todo: la copia te avisará)' })"
    }
    $txt += "`n`nLo que has quitado del plan no se borra de los discos. Los cambios se aplican en la próxima copia."
    if ((Dialogo $ed.Win "Guardar el plan" $txt @('Cancelar', 'Guardar plan') 'Guardar plan') -ne 'Guardar plan') { return }
    EscribirCarpetas $ed.Carpetas.ToArray()
    GuardarLista $FicheroDivididas $ed.Div
    GuardarLista $FicheroExcluidas $ed.Exc
    $rep = @{}; foreach ($k in $ed.Rep.Keys) { $rep[$k] = $ed.Rep[$k] }
    GuardarReparto $rep
    GuardarTamUnidades $ed.Tam
    $ed.Guardado = $true; $ed.Win.Close()
    if ($ed.AlGuardar) { & $ed.AlGuardar }
}
