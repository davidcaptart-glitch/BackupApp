# ============================================================
#  VENTANA PRINCIPAL: una sola ventana para todo
#  A la izquierda, el menu; a la derecha, la pantalla elegida (Inicio, Copia, Editar el plan, Liberar espacio,
#  Explorar discos, Tamanos, Asistente). Las pantallas de los demas modulos se siguen creando como ventanas
#  (NuevaVentana) pero no se muestran sueltas: su contenido se mueve aqui dentro (MostrarVista). Cuando el codigo de
#  una pantalla la "cierra" (Close), sale de aqui y se vuelve a Inicio.
#  La copia corre en otro proceso para que esta ventana no se cuelgue nunca: aqui se ve lo que hace
#  (copia_estado.json), se contestan sus preguntas (pregunta.json) y se muestra el resultado.
#  Lo carga bandeja.ps1 despues de los demas modulos.
# ============================================================
$script:Principal = $null
$MenuPrincipal = @(
    @{ Clave = 'Inicio';                   Texto = 'Inicio';          Glifo = 0xE80F; Abrir = { MostrarPlan } }
    @{ Clave = 'Copia';                    Texto = 'Copia';           Glifo = 0xE896; Abrir = { MostrarCopia } }
    @{ Clave = 'Editar el plan de copias'; Texto = 'Editar el plan';  Glifo = 0xE70F; Abrir = { MostrarEditorPlan 'AsistenteTerminado' } }
    @{ Clave = 'Liberar espacio';          Texto = 'Liberar espacio'; Glifo = 0xE74D; Abrir = { MostrarLiberarEspacio } }
    @{ Clave = 'Explorar discos';          Texto = 'Explorar discos'; Glifo = 0xE8B7; Abrir = { MostrarExplorador } }
    @{ Clave = 'Tamaño de las carpetas';   Texto = 'Tamaños';         Glifo = 0xE9D2; Abrir = { MostrarTamanos } }
    @{ Clave = 'Asistente';                Texto = 'Asistente';       Glifo = 0xE82D; Abrir = { AbrirAsistente } }
)

$XamlPrincipal = @"
<Window $VentanaBase Title="BackupApp" Width="1180" Height="800" MinWidth="900" MinHeight="580" WindowStartupLocation="CenterScreen">
  <Window.Resources>
    <Style x:Key="Nav" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{DynamicResource Texto}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="RadioButton">
          <Border x:Name="Bd" Background="Transparent" CornerRadius="6" Padding="12,9" Margin="0,0,0,2"><ContentPresenter/></Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource Fondo}"/></Trigger>
            <Trigger Property="IsChecked" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource AcentoSuave}"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="230"/><ColumnDefinition/></Grid.ColumnDefinitions>
    <Border Background="{DynamicResource Tarjeta}" BorderBrush="{DynamicResource Borde}" BorderThickness="0,0,1,0">
      <DockPanel Margin="12,18,12,14">
        <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="8,0,0,20">
          <Image x:Name="Logo" Width="28" Height="28"/>
          <TextBlock Text="BackupApp" FontSize="19" FontWeight="SemiBold" Margin="10,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel DockPanel.Dock="Bottom">
          <Border x:Name="Actividad" Visibility="Collapsed" Cursor="Hand" CornerRadius="8" Padding="12,10" Margin="0,0,0,12" Background="{DynamicResource Fondo}" BorderBrush="{DynamicResource Borde}" BorderThickness="1">
            <StackPanel>
              <DockPanel>
                <TextBlock x:Name="ActPct" DockPanel.Dock="Right" FontWeight="SemiBold" Foreground="{DynamicResource Acento}" Margin="8,0,0,0"/>
                <TextBlock x:Name="ActTitulo" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
              </DockPanel>
              <TextBlock x:Name="ActDetalle" FontSize="11.5" Foreground="{DynamicResource Texto2}" Margin="0,3,0,6" TextTrimming="CharacterEllipsis"/>
              <ProgressBar x:Name="ActBarra" Height="4" Minimum="0" Maximum="1" BorderThickness="0" Foreground="{DynamicResource Acento}" Background="{DynamicResource Barra}"/>
            </StackPanel>
          </Border>
          <Button x:Name="BtnAct" Content="Buscar actualizaciones" Style="{DynamicResource Enlace}" HorizontalAlignment="Left" Margin="12,0,0,0"/>
          <TextBlock x:Name="Version" FontSize="11" Foreground="{DynamicResource Texto2}" Margin="12,6,0,0"/>
        </StackPanel>
        <StackPanel x:Name="Menu"/>
      </DockPanel>
    </Border>
    <ContentControl x:Name="Host" Grid.Column="1" Focusable="False"/>
  </Grid>
</Window>
"@

function AbrirPrincipal {
    $p = $script:Principal
    if ($p -and $p.Win.IsVisible) {
        if ($p.Win.WindowState -eq 'Minimized') { $p.Win.WindowState = 'Normal' }
        [void]$p.Win.Activate(); return $p
    }
    $w = NuevaVentana $XamlPrincipal
    $p = @{ Win = $w; Host = $w.FindName('Host'); Vistas = @{}; Actual = $null; Botones = @{}; Cerrando = $false }
    $script:Principal = $p
    foreach ($m in $MenuPrincipal) {
        $rb = New-Object Windows.Controls.RadioButton; $rb.Style = $w.FindResource('Nav'); $rb.GroupName = 'menu'; $rb.Tag = $m.Clave
        $f = Fila @((Icono ([string][char]$m.Glifo) 16 'Acento'), (Texto $m.Texto 13.5)) @('Auto', '*'); $f.Children[1].Margin = '12,0,0,0'
        $rb.Content = $f
        $rb.add_Click({ param($s, $e) $m = $MenuPrincipal | Where-Object { $_.Clave -eq $s.Tag } | Select-Object -First 1; & $m.Abrir })
        [void]$w.FindName('Menu').Children.Add($rb); $p.Botones[$m.Clave] = $rb
    }
    $logo = RutaRecurso "logo.png"
    if ($logo) { try { $w.FindName('Logo').Source = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri $logo), [Windows.Media.Imaging.BitmapCreateOptions]::None, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad) } catch {} }
    $w.FindName('Version').Text = "Versión $Version"
    $w.FindName('BtnAct').add_Click({ IniciarBusqueda $true })
    $w.FindName('Actividad').add_MouseLeftButtonUp({ MostrarCopia })
    $w.add_Closing({ param($s, $e) CerrandoPrincipal $e })
    $w.add_Closed({ $script:Principal = $null })
    MostrarVentanaReal $w
    PintarActividad
    return $p
}
function MostrarVista($w) {
    # Pone una pantalla (una ventana creada con NuevaVentana) dentro de la ventana principal y la selecciona en el menu
    $p = AbrirPrincipal
    $clave = "$($w.Title)"
    $v = $p.Vistas[$clave]
    if (-not $v -or $v.Win -ne $w) {
        if ($v) { [void]$p.Vistas.Remove($clave); try { $v.Win.Close() } catch {} }   # habia otra pantalla igual: se cierra
        $c = $w.Content; $w.Content = $null
        $v = @{ Win = $w; Contenido = $c }
        $p.Vistas[$clave] = $v
        $w.add_Closed({ param($s, $e) QuitarVista $s })
    }
    $p.Host.Content = $v.Contenido
    $p.Actual = $clave
    foreach ($k in @($p.Botones.Keys)) { $p.Botones[$k].IsChecked = ($k -eq $clave) }
}
function QuitarVista($w) {
    # El codigo de una pantalla la ha cerrado: sale de la ventana principal y, si era la que se veia, se vuelve a Inicio
    $p = $script:Principal; if (-not $p) { return }
    $clave = @($p.Vistas.Keys | Where-Object { $p.Vistas[$_].Win -eq $w }) | Select-Object -First 1
    if (-not $clave) { return }
    [void]$p.Vistas.Remove($clave)
    if ($p.Actual -eq $clave) {
        $p.Host.Content = $null; $p.Actual = $null
        if (-not $p.Cerrando) { MostrarPlan }
    }
}
function CerrandoPrincipal($e) {
    # Al cerrar la ventana se cierran sus pantallas (paran sus busquedas). Si alguna no quiere cerrarse (el editor
    # con cambios sin guardar), la ventana se queda abierta en esa pantalla. El icono y la copia siguen.
    $p = $script:Principal; if (-not $p) { return }
    $p.Cerrando = $true
    foreach ($v in @($p.Vistas.Values)) { try { $v.Win.Close() } catch {} }
    $p.Cerrando = $false
    if ($p.Vistas.Count) {
        $e.Cancel = $true
        $k = @($p.Vistas.Keys)[0]; MostrarVista $p.Vistas[$k].Win
    }
}

# ---------- Pantalla «Copia» ----------
$XamlCopia = @"
<Window $VentanaBase Title="Copia">
  <Grid Margin="34,28,34,24">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/></Grid.RowDefinitions>
    <DockPanel>
      <Button x:Name="BtnCopiar" DockPanel.Dock="Right" Content="Hacer copia ahora" Style="{DynamicResource Primario}" MinWidth="170" VerticalAlignment="Center"/>
      <TextBlock Text="Copia de seguridad" FontSize="28" FontWeight="SemiBold" FontFamily="Segoe UI Variable Display, Segoe UI"/>
    </DockPanel>
    <TextBlock x:Name="Estado" Grid.Row="1" Foreground="{DynamicResource Texto2}" Margin="0,6,0,16" TextWrapping="Wrap"/>
    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0,0,10,0">
      <StackPanel>
        <Border x:Name="Tarjeta" Visibility="Collapsed" Background="{DynamicResource Tarjeta}" BorderBrush="{DynamicResource Borde}" BorderThickness="1" CornerRadius="8" Padding="20,16" Margin="0,0,0,10">
          <StackPanel>
            <DockPanel>
              <TextBlock x:Name="Pct" DockPanel.Dock="Right" FontSize="24" FontWeight="SemiBold" Foreground="{DynamicResource Acento}" Margin="12,0,0,0"/>
              <TextBlock x:Name="Titulo" FontSize="18" FontWeight="SemiBold" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
            </DockPanel>
            <TextBlock x:Name="Detalle" Foreground="{DynamicResource Texto2}" Margin="0,6,0,12" TextTrimming="CharacterEllipsis"/>
            <ProgressBar x:Name="Barra" Height="6" Minimum="0" Maximum="1" BorderThickness="0" Foreground="{DynamicResource Acento}" Background="{DynamicResource Barra}"/>
            <TextBlock x:Name="Cuenta" Foreground="{DynamicResource Texto2}" Margin="0,10,0,0" TextWrapping="Wrap"/>
            <DockPanel Margin="0,16,0,0">
              <Button x:Name="BtnDetener" DockPanel.Dock="Right" Content="Detener" MinWidth="110"/>
              <TextBlock FontSize="11.5" Foreground="{DynamicResource Texto2}" TextWrapping="Wrap" VerticalAlignment="Center" Margin="0,0,16,0" Text="Puedes seguir usando BackupApp y el PC mientras copia. Si la detienes, lo ya copiado se conserva y la próxima vez sigue donde se quedó."/>
            </DockPanel>
          </StackPanel>
        </Border>
        <Border x:Name="Resultado" Visibility="Collapsed" Background="{DynamicResource Tarjeta}" BorderBrush="{DynamicResource Borde}" BorderThickness="1" CornerRadius="8" Padding="20,16" Margin="0,0,0,10">
          <StackPanel>
            <TextBlock x:Name="ResTitulo" FontSize="17" FontWeight="SemiBold"/>
            <TextBlock x:Name="ResFecha" FontSize="11.5" Foreground="{DynamicResource Texto2}" Margin="0,2,0,10"/>
            <TextBlock x:Name="ResTexto" TextWrapping="Wrap" LineHeight="20"/>
            <StackPanel Orientation="Horizontal" Margin="0,16,0,0">
              <Button x:Name="BtnElegir" Content="Elegir qué borrar del PC" Style="{DynamicResource Primario}" Margin="0,0,8,0"/>
              <Button x:Name="BtnRegistro" Content="Ver el registro"/>
            </StackPanel>
          </StackPanel>
        </Border>
        <TextBlock x:Name="Nada" Visibility="Collapsed" Foreground="{DynamicResource Texto2}" TextWrapping="Wrap" Text="Todavía no has hecho ninguna copia desde aquí. Pulsa «Hacer copia ahora» con tu disco de backup conectado."/>
      </StackPanel>
    </ScrollViewer>
  </Grid>
</Window>
"@
$script:vistaCopia = $null
function MostrarCopia {
    if (-not ($script:vistaCopia -and (VentanaAbierta $script:vistaCopia))) {
        $w = NuevaVentana $XamlCopia
        $w.FindName('BtnCopiar').add_Click({ LanzarCopia })
        $w.FindName('BtnDetener').add_Click({ param($s, $e)
            Set-Content -LiteralPath $FicheroDetener 'detener' -ErrorAction SilentlyContinue; $s.IsEnabled = $false; $s.Content = "Deteniendo..." })
        $w.FindName('BtnElegir').add_Click({ $r = "$($script:copiaEstado.Resultado.Explorar)"; MostrarExplorador $(if ($r -and (Test-Path -LiteralPath $r)) { $r } else { $null }) })
        $w.FindName('BtnRegistro').add_Click({ $l = "$($script:copiaEstado.Log)"; if ($l -and (Test-Path -LiteralPath $l)) { Start-Process notepad.exe "`"$l`"" } else { New-Item -ItemType Directory -Path $CarpetaLogs -Force | Out-Null; Start-Process explorer.exe $CarpetaLogs } })
        $w.add_Closed({ $script:vistaCopia = $null })
        $script:vistaCopia = $w
    }
    MostrarSinBloquear $script:vistaCopia
    PintarCopia
}
function CopiaActiva { $e = $script:copiaEstado; return [bool]($e -and $e.Fase -ne 'fin' -and $e.Pid -and (Get-Process -Id $e.Pid -ErrorAction SilentlyContinue)) }
function PintarCopia {
    $w = $script:vistaCopia; if (-not $w) { return }
    $e = $script:copiaEstado; $activa = CopiaActiva
    $otra = (-not $activa) -and (Copiando)   # copia sin estado: la lanzo una version anterior (con su propia ventana) o se esta preparando
    $t = $w.FindName('Tarjeta'); $r = $w.FindName('Resultado'); $b = $w.FindName('BtnCopiar'); $d = $w.FindName('BtnDetener')
    $b.IsEnabled = -not ($activa -or $otra); $b.Content = if ($activa -or $otra) { "Copiando..." } else { "Hacer copia ahora" }
    if ($activa) {
        $t.Visibility = 'Visible'
        $w.FindName('Titulo').Text = "$($e.Titulo)"; $w.FindName('Detalle').Text = "$($e.Detalle)"; $w.FindName('Cuenta').Text = "$($e.Cuenta)"
        $f = [math]::Max(0.0, [math]::Min(1.0, [double]$e.Fraccion)); $w.FindName('Barra').Value = $f
        $w.FindName('Pct').Text = if ($f -gt 0) { "{0:N0} %" -f [math]::Floor($f * 100) } else { "" }
        if (-not (Test-Path -LiteralPath $FicheroDetener)) { $d.IsEnabled = $true; $d.Content = "Detener" }
        $w.FindName('Estado').Text = if ($e.Fase -eq 'pregunta') { "La copia está esperando tu respuesta." } else { "Copia en marcha desde las $(([datetime]$e.Inicio).ToString('HH:mm'))." }
    } elseif ($otra) {
        $t.Visibility = 'Visible'
        $w.FindName('Titulo').Text = "Hay una copia en marcha"; $w.FindName('Pct').Text = ""; $w.FindName('Barra').Value = 0
        $w.FindName('Detalle').Text = "Se está preparando, o la empezó una versión anterior de BackupApp en su propia ventana."; $w.FindName('Cuenta').Text = ""
        $d.IsEnabled = $false
        $w.FindName('Estado').Text = "Copia en marcha."
    } else {
        $t.Visibility = 'Collapsed'
        $w.FindName('Estado').Text = "No hay ninguna copia en marcha."
    }
    $res = if ($e) { $e.Resultado } else { $null }
    if ($res -and -not $activa) {
        $r.Visibility = 'Visible'
        $w.FindName('ResTitulo').Text = "$($res.Titulo)"; $w.FindName('ResTexto').Text = "$($res.Texto)"
        $w.FindName('ResFecha').Text = if ($res.Fecha) { "Terminó el $(([datetime]$res.Fecha).ToString('dd/MM/yyyy')) a las $(([datetime]$res.Fecha).ToString('HH:mm'))" } else { "" }
        $w.FindName('BtnElegir').Visibility = if ($res.Explorar) { 'Visible' } else { 'Collapsed' }
    } else { $r.Visibility = 'Collapsed' }
    $w.FindName('Nada').Visibility = if (-not $activa -and -not $otra -and -not $res) { 'Visible' } else { 'Collapsed' }
}
function PintarActividad {
    # Recuadro del menu: siempre a la vista lo que se esta haciendo
    $p = $script:Principal; if (-not $p) { return }
    $w = $p.Win; $a = $w.FindName('Actividad'); $e = $script:copiaEstado
    if (CopiaActiva) {
        $a.Visibility = 'Visible'
        $f = [math]::Max(0.0, [math]::Min(1.0, [double]$e.Fraccion))
        $w.FindName('ActTitulo').Text = if ($e.Fase -eq 'pregunta') { "Esperando tu respuesta" } else { "$($e.Titulo)" }
        $w.FindName('ActDetalle').Text = "$($e.Cuenta)"; $w.FindName('ActBarra').Value = $f
        $w.FindName('ActPct').Text = if ($f -gt 0) { "{0:N0} %" -f [math]::Floor($f * 100) } else { "" }
    } elseif (Copiando) {
        $a.Visibility = 'Visible'; $w.FindName('ActTitulo').Text = "Copia en marcha"; $w.FindName('ActDetalle').Text = ""; $w.FindName('ActPct').Text = ""; $w.FindName('ActBarra').Value = 0
    } else { $a.Visibility = 'Collapsed' }
}

# ---------- Lo que pasa en la copia: se revisa cada medio segundo ----------
$script:copiaEstado = LeerJson $FicheroEstadoCopia
$script:finVisto = if ($script:copiaEstado) { $script:copiaEstado.Id } else { $null }   # lo que ya habia al arrancar no se avisa
$script:estadoMarca = $null; $script:preguntando = $false; $script:ultimaPregunta = $null; $script:ultimoLatido = [datetime]::MinValue
function RevisarActividad {
    # Latido: la copia sabe que hay alguien mirando y no abre ventana propia
    if (((Get-Date) - $script:ultimoLatido).TotalSeconds -ge 5) { $script:ultimoLatido = Get-Date; try { [IO.File]::WriteAllText($FicheroLatido, "$PID") } catch {} }
    $cambio = $false
    if (Test-Path -LiteralPath $FicheroEstadoCopia) {
        $m = (Get-Item -LiteralPath $FicheroEstadoCopia).LastWriteTimeUtc
        if ($m -ne $script:estadoMarca) { $script:estadoMarca = $m; $n = LeerJson $FicheroEstadoCopia; if ($n) { $script:copiaEstado = $n; $cambio = $true } }
    }
    $e = $script:copiaEstado
    # La copia se cerro sin llegar al final (apagado, error grave): se dice, lo copiado se conserva
    if ($e -and $e.Fase -ne 'fin' -and $e.Pid -and -not (Get-Process -Id $e.Pid -ErrorAction SilentlyContinue)) {
        $e.Fase = 'fin'
        $e | Add-Member -NotePropertyName Resultado -NotePropertyValue ([pscustomobject]@{ Titulo = "La copia se cerró sin terminar"; Texto = "Lo ya copiado se conserva: la próxima copia seguirá donde se quedó."; Fecha = (Get-Date).ToString('o'); Explorar = $null }) -Force
        EscribirJson $FicheroEstadoCopia $e; $cambio = $true
    }
    $cp = Copiando
    if ($cp -ne $script:copiandoAntes) {
        # Empieza o acaba una copia: Inicio cambia su boton y su texto
        $script:copiandoAntes = $cp; $cambio = $true
        if ($script:ventanaPrincipal -and (VentanaAbierta $script:ventanaPrincipal)) { EstadoPrincipal $script:ventanaPrincipal }
    }
    if ($cambio -or $cp) { PintarActividad; PintarCopia }
    # Preguntas de la copia: se contestan aqui, sobre la ventana principal
    if (-not $script:preguntando -and (Test-Path -LiteralPath $FicheroPregunta)) {
        $q = LeerJson $FicheroPregunta
        if ($q -and $q.Id -ne $script:ultimaPregunta) {
            $script:preguntando = $true
            try {
                MostrarCopia
                $bot = @($q.Botones)
                $r = Dialogo $script:Principal.Win "$($q.Titulo)" "$($q.Texto)" $bot "$($q.Primario)"
                if (-not $r) { $r = $bot[0] }
                EscribirJson $FicheroRespuesta ([pscustomobject]@{ Id = $q.Id; Boton = $r })
                $script:ultimaPregunta = $q.Id
            } finally { $script:preguntando = $false }
        }
    }
    # Copia terminada: se ensena el resultado (o se avisa si la ventana esta cerrada)
    if ($e -and $e.Fase -eq 'fin' -and $e.Id -ne $script:finVisto) {
        $script:finVisto = $e.Id
        if ($script:Principal -and $script:Principal.Win.IsVisible) { MostrarCopia }
        else { Avisar "$($e.Resultado.Titulo)" "Haz clic para ver el resultado." 'copia' }
    }
}
