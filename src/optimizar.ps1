# ============================================================
#  LIBERAR ESPACIO (menu del escudo y avisos de optimizacion)
#  Busca en pocos segundos lo que se puede borrar sin perder nada importante: papelera, temporales, caches,
#  instaladores y comprimidos antiguos o repetidos en Descargas, carpetas que se regeneran (node_modules,
#  previas de Lightroom). El usuario marca que borrar; se manda a la papelera o se borra del todo, siempre
#  despues de confirmar. Nunca se borra nada sin preguntar.
# ============================================================
$GlifoEscoba = [string][char]0xE74D; $GlifoDiscoDuro = [string][char]0xEDA2

function CarpetaDescargas {
    try { $p = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path; if ($p -and (Test-Path -LiteralPath $p)) { return $p } } catch {}
    return (Join-Path $env:USERPROFILE "Downloads")
}
function ContenidoDe($dir, $diasMin = 0) {
    # Lo que hay dentro de una carpeta (primer nivel), opcionalmente solo lo que no se ha tocado en $diasMin dias
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $limite = (Get-Date).AddDays(-$diasMin)
    @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue | Where-Object { $diasMin -le 0 -or $_.LastWriteTime -lt $limite } | ForEach-Object { $_.FullName })
}
function BytesDe($rutas) {
    $t = [int64]0
    foreach ($r in $rutas) { $i = Get-Item -LiteralPath $r -Force -ErrorAction SilentlyContinue; if (-not $i) { continue }; if ($i.PSIsContainer) { $t += (Analizar $r).Bytes } else { $t += $i.Length } }
    return $t
}
function Oportunidad($id, $titulo, $detalle, $rutas, $seguro, $bytes = $null, $tipo = 'archivos') {
    $rutas = @($rutas)
    if ($null -eq $bytes) { $bytes = BytesDe $rutas }
    [pscustomobject]@{ Id = $id; Titulo = $titulo; Detalle = $detalle; Rutas = $rutas; Bytes = [int64]$bytes; Seguro = $seguro; Tipo = $tipo }
}
function BuscarCarpetasConNombre($raices, $patron, $prof = 6) {
    # Carpetas cuyo nombre encaja con $patron dentro de $raices (sin entrar en ellas ni en las que se saltan)
    $pila = New-Object System.Collections.Stack
    foreach ($r in $raices) { if ($r -and (Test-Path -LiteralPath $r)) { $pila.Push(@((New-Object IO.DirectoryInfo $r), 0)) } }
    $vistas = 0
    while ($pila.Count) {
        $d, $n = $pila.Pop()
        $vistas++; if ($script:estadoBusq -and $vistas % 500 -eq 0) { $script:estadoBusq.Paso = "Buscando carpetas que se regeneran (node_modules, previas de Lightroom): {0:N0} carpetas revisadas..." -f $vistas }
        try {
            foreach ($s in $d.EnumerateDirectories()) {
                if ($s.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($s.Name -match $patron) { $s; continue }
                if ($n -lt $prof -and $s.Name -notmatch '^(\.git|\$Recycle\.Bin|Windows|AppData)$') { $pila.Push(@($s, ($n + 1))) }
            }
        } catch {}
    }
}

function LetrasPorDefecto {
    # Discos que se miran al liberar espacio: los fijos, menos los de backup (salvo que el usuario los marque)
    $backup = @(DiscosConectados | ForEach-Object { $_.Letra.ToUpper() })
    $si = @(LeerAjuste 'LiberarMirar' @()); $no = @(LeerAjuste 'LiberarSinMirar' @())
    @(EstadoUnidades | ForEach-Object { $_.Letra.ToUpper() } | Where-Object { $si -contains $_ -or ($no -notcontains $_ -and $backup -notcontains $_) })
}
function EnLetras($ruta) {
    if ($null -eq $script:letrasBusq) { return $true }
    $r = "$ruta"; return ($r.Length -ge 2 -and $script:letrasBusq -contains $r.Substring(0, 2).ToUpper())
}
function PasoBusqueda($txt, [double]$frac) { if ($script:estadoBusq) { $script:estadoBusq.Paso = $txt; $script:estadoBusq.Frac = $frac } }

# $letras: discos donde buscar ("C:", "D:"...; por defecto LetrasPorDefecto).
# $estado: tabla sincronizada para la ventana, que va pintando lo encontrado (Items, Ver) y el paso (Paso, Frac, Fin).
function BuscarOportunidades($letras = $null, $estado = $null) {
    if ($null -eq $letras) { $letras = LetrasPorDefecto }
    $script:letrasBusq = @($letras | ForEach-Object { "$_".Substring(0, 2).ToUpper() })
    $script:estadoBusq = $estado
    $o = New-Object System.Collections.Generic.List[object]
    function Anadir($x) { $o.Add($x); if ($script:estadoBusq -and $x.Bytes -gt 0) { [void]$script:estadoBusq.Items.Add($x); $script:estadoBusq.Ver++ } }
    # 1) Papelera (solo la de los discos elegidos)
    PasoBusqueda "Mirando la papelera..." 0.02
    try {
        # SHQueryRecycleBin da el tamano de la papelera de cada disco al momento (recorrerla elemento a elemento tardaba casi un minuto)
        if (-not ('BackupApp.Papelera' -as [type])) {
            Add-Type -Namespace BackupApp -Name Papelera -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct Info { public int cbSize; public long Bytes; public long Elementos; }
[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SHQueryRecycleBin(string raiz, ref Info info);
'@
        }
        $b = [int64]0; $n = 0; $ls = @{}
        foreach ($l in $script:letrasBusq) {
            $i = New-Object BackupApp.Papelera+Info; $i.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($i)
            if ([BackupApp.Papelera]::SHQueryRecycleBin("$l\", [ref]$i) -eq 0 -and $i.Elementos -gt 0) { $b += $i.Bytes; $n += $i.Elementos; $ls[$l] = $true }
        }
        if ($b -gt 10MB) {
            $x = Oportunidad 'papelera' "Vaciar la papelera" "$n elementos que ya borraste ($(@($ls.Keys | Sort-Object) -join ', ')). Al vaciarla no se pueden recuperar." @() $true $b 'papelera'
            $x | Add-Member -NotePropertyName Letras -NotePropertyValue @($ls.Keys); Anadir $x
        }
    } catch {}
    # 2) Temporales (solo lo que lleva mas de 7 dias: lo reciente puede estar en uso)
    PasoBusqueda "Mirando los archivos temporales..." 0.06
    $tmp = if (EnLetras $env:TEMP) { ContenidoDe $env:TEMP 7 } else { @() }
    if ($tmp) { Anadir((Oportunidad 'temp' "Archivos temporales" "Restos que dejan los programas en %TEMP% hace más de una semana." $tmp $true)) }
    # 3) Caches que se regeneran solas
    $LA = $env:LOCALAPPDATA; $RA = $env:APPDATA; $H = $env:USERPROFILE
    $caches = @(
        @('Caché de Google Chrome', "$LA\Google\Chrome\User Data\Default\Cache"), @('Caché de Microsoft Edge', "$LA\Microsoft\Edge\User Data\Default\Cache"),
        @('Caché de sombreadores de DirectX', "$LA\D3DSCache"), @('Informes de errores de programas', "$LA\CrashDumps"),
        @('Caché de npm', "$LA\npm-cache"), @('Caché de pip', "$LA\pip\Cache"),
        @('Caché de medios de Adobe', "$RA\Adobe\Common\Media Cache Files"), @('Caché de medios de Adobe', "$RA\Adobe\Common\Media Cache"))
    PasoBusqueda "Mirando las cachés de los programas..." 0.10
    foreach ($c in $caches) {
        if (-not (EnLetras $c[1])) { continue }
        $r = ContenidoDe $c[1]
        if (-not $r) { continue }
        $x = Oportunidad "cache:$($c[1])" $c[0] "Se vuelve a crear sola cuando hace falta. Mejor con el programa cerrado." $r $true
        if ($x.Bytes -ge 100MB) { Anadir $x }
    }
    # 4) Descargas: instaladores y comprimidos de mas de 30 dias, repetidos y lo que lleva 6 meses sin tocar
    PasoBusqueda "Mirando la carpeta Descargas..." 0.18
    $desc = CarpetaDescargas
    $arch = @(if (EnLetras $desc) { Get-ChildItem -LiteralPath $desc -File -Recurse -Force -ErrorAction SilentlyContinue })
    $hace30 = (Get-Date).AddDays(-30); $hace180 = (Get-Date).AddDays(-180)
    $inst = @($arch | Where-Object { $_.Extension -match '^\.(exe|msi|msix|appx)$' -and $_.LastWriteTime -lt $hace30 })
    if ($inst) { Anadir((Oportunidad 'desc:inst' "Instaladores antiguos en Descargas" "$($inst.Count) instaladores de hace más de un mes. Si el programa ya está instalado, no hacen falta." ($inst | ForEach-Object { $_.FullName }) $false)) }
    $zip = @($arch | Where-Object { $_.Extension -match '^\.(zip|rar|7z|iso)$' -and $_.LastWriteTime -lt $hace30 -and (Test-Path -LiteralPath (Join-Path $_.DirectoryName $_.BaseName)) })
    if ($zip) { Anadir((Oportunidad 'desc:zip' "Comprimidos ya descomprimidos" "$($zip.Count) archivos .zip/.rar que ya tienen al lado su carpeta descomprimida." ($zip | ForEach-Object { $_.FullName }) $false)) }
    $rep = @()
    foreach ($g in ($arch | Where-Object { $_.Length -gt 1MB } | Group-Object Length | Where-Object { $_.Count -gt 1 })) {
        foreach ($h in ($g.Group | Group-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm MD5 -ErrorAction SilentlyContinue).Hash } | Where-Object { $_.Name -and $_.Count -gt 1 })) {
            $rep += @($h.Group | Sort-Object LastWriteTime | Select-Object -Skip 1)   # se queda la copia mas antigua
        }
    }
    if ($rep) { Anadir((Oportunidad 'desc:rep' "Archivos repetidos en Descargas" "$($rep.Count) archivos descargados dos veces o más. Se deja una copia de cada uno." ($rep | ForEach-Object { $_.FullName }) $false)) }
    $ya = @($inst + $zip + $rep | ForEach-Object { $_.FullName })
    $viejo = @($arch | Where-Object { $_.LastWriteTime -lt $hace180 -and $ya -notcontains $_.FullName })
    if ($viejo) { Anadir((Oportunidad 'desc:viejo' "Descargas sin tocar en 6 meses" "$($viejo.Count) archivos. Revísalos antes: puede haber algo que quieras guardar." ($viejo | ForEach-Object { $_.FullName }) $false)) }
    # 5) Carpetas que se regeneran, dentro de las carpetas del backup y de Imagenes
    PasoBusqueda "Buscando carpetas que se regeneran (node_modules, previas de Lightroom)..." 0.30
    $raices = @(@($Carpetas | ForEach-Object { $_.Origen }) + @([Environment]::GetFolderPath('MyPictures')) | Where-Object { EnLetras $_ } | Select-Object -Unique)
    $nm = @(BuscarCarpetasConNombre $raices '^node_modules$' | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) })
    if ($nm) { Anadir((Oportunidad 'node_modules' "node_modules de proyectos parados" "$($nm.Count) carpetas de proyectos sin tocar en 3 meses. Se recuperan con «npm install»." ($nm | ForEach-Object { $_.FullName }) $false)) }
    PasoBusqueda "Buscando previas de Lightroom..." 0.38
    $lr = @(BuscarCarpetasConNombre $raices 'Previews\.lrdata$' | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) })
    if ($lr) { Anadir((Oportunidad 'lightroom' "Previas de Lightroom antiguas" "$($lr.Count) catálogos sin abrir en 3 meses. Lightroom las vuelve a crear al abrir el catálogo." ($lr | ForEach-Object { $_.FullName }) $false)) }
    # 6) Subcarpetas que ya tienen una copia al dia en un disco de backup (sin cambios desde la ultima copia)
    $discos = @(LeerDiscos); $rep = LeerReparto; $unid = @(UnidadesActuales); $tam = TamanosDe $unid
    # Solo las que tienen disco con alguna copia hecha (medir cada una es lo que mas tarda)
    $conCopia = @{}; foreach ($d in $discos) { if ($d.UltimaCopia) { $conCopia[$d.Id] = $true } }
    $cand = @($unid | Where-Object { $_.Tipo -eq 'carpeta' -and (EnLetras $_.Clave) -and [int64]$tam[$_.Clave] -ge 1GB -and $conCopia[$rep[$_.Clave]] }); $k = 0
    foreach ($u in $cand) {
        $k++; PasoBusqueda "Buscando lo que ya está copiado en tus discos de backup ($k de $($cand.Count))..." (0.45 + 0.55 * ($k - 1) / [math]::Max(1.0, $cand.Count))
        $d = $discos | Where-Object { $_.Id -eq $rep[$u.Clave] } | Select-Object -First 1
        if (-not $d -or -not $d.UltimaCopia -or [int64]$tam[$u.Clave] -lt 1GB) { continue }
        # UltimaCopia solo guarda los minutos: se toma el final de ese minuto (antes de borrar se comprueba igualmente que la copia es identica)
        $copia = [datetime]::ParseExact($d.UltimaCopia, 'yyyy-MM-dd HH:mm', $null).AddSeconds(59)
        $a = Analizar $u.Clave
        if ($a.Ultimo -ge $copia) { continue }   # ha cambiado despues de la copia
        Anadir([pscustomobject]@{ Id = "copiado:$($u.Clave)"; Titulo = $u.Nombre; Rutas = @($u.Clave); Bytes = [int64]$a.Bytes; Seguro = $false; Tipo = 'copiado'
            Detalle = "$(Split-Path $u.Clave -Parent)   $([char]0x00B7)   copiada en «$($d.Nombre)» el $($copia.ToString('dd/MM/yyyy'))   $([char]0x00B7)   sin cambios desde el $($a.Ultimo.ToString('dd/MM/yyyy'))"
            Disco = $d.Id; DiscoNombre = $d.Nombre; Destino = (DestinoUnidad $u) })
    }
    PasoBusqueda "Listo" 1.0; if ($script:estadoBusq) { $script:estadoBusq.Fin = $true }
    # Primero lo que se regenera o sobra; al final, lo que ya esta copiado
    return @($o.ToArray() | Where-Object { $_.Bytes -gt 0 } | Sort-Object { $_.Tipo -eq 'copiado' }, { -$_.Bytes })
}
function EstadoUnidades {
    # Unidades internas con su ocupacion (para la cabecera y para el aviso de poco espacio)
    foreach ($dr in (UnidadesDeDisco)) {
        if ($dr.DriveType -ne 'Fixed') { continue }
        [pscustomobject]@{ Letra = $dr.Name.Substring(0, 2); Etiqueta = $dr.VolumeLabel; Total = [int64]$dr.TotalSize; Libre = [int64]$dr.AvailableFreeSpace
                           PocoEspacio = ($dr.AvailableFreeSpace -lt 0.1 * $dr.TotalSize) }
    }
}

# ---------- Busqueda en segundo plano (para los avisos y para no congelar la ventana) ----------
function BuscarOportunidadesEnSegundoPlano {
    if ($script:busquedaOpt) { return }
    $ps = [powershell]::Create()
    [void]$ps.AddScript({ param($config, $opt) . $config; . $opt; ,@(BuscarOportunidades) }.ToString())
    [void]$ps.AddArgument((Join-Path $Codigo "config.ps1")); [void]$ps.AddArgument((Join-Path $Codigo "optimizar.ps1"))
    $script:busquedaOpt = @{ PS = $ps; H = $ps.BeginInvoke() }
}
function ResultadoOportunidades {
    if (-not $script:busquedaOpt -or -not $script:busquedaOpt.H.IsCompleted) { return $null }
    try { $r = @($script:busquedaOpt.PS.EndInvoke($script:busquedaOpt.H) | ForEach-Object { $_ }) } catch { $r = @() }
    $script:busquedaOpt.PS.Dispose(); $script:busquedaOpt = $null
    return , $r
}

# ---------- Ventana ----------
$XamlLiberar = @"
<Window $VentanaBase Title="Liberar espacio" Width="900" Height="720" MinWidth="700" MinHeight="520" WindowStartupLocation="CenterScreen">
  <Grid Margin="34,28,34,24">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Liberar espacio" FontSize="28" FontWeight="SemiBold" FontFamily="Segoe UI Variable Display, Segoe UI"/>
    <TextBlock Grid.Row="1" Foreground="{DynamicResource Texto2}" Margin="0,6,0,16" TextWrapping="Wrap" Text="Marca lo que quieres borrar. Lo que está marcado de entrada se regenera solo o ya lo habías borrado; lo demás, revísalo. Nada se borra sin que lo confirmes."/>
    <UniformGrid x:Name="Unidades" Grid.Row="2" Rows="1" Margin="0,0,0,12"/>
    <ScrollViewer Grid.Row="3" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0,0,10,0"><StackPanel x:Name="Lista"/></ScrollViewer>
    <Grid Grid.Row="4" Margin="0,18,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel VerticalAlignment="Center">
        <StackPanel Orientation="Horizontal">
          <RadioButton x:Name="ModoPapelera" Style="{DynamicResource Pastilla}" GroupName="Modo" Content="Enviar a la papelera" IsChecked="True"/>
          <RadioButton x:Name="ModoBorrar" Style="{DynamicResource Pastilla}" GroupName="Modo" Content="Borrar definitivamente"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Margin="12,8,0,0">
          <Button x:Name="BtnExplorar" Content="Explorar los discos y elegir yo qué borrar" Style="{DynamicResource Enlace}" Margin="0,0,18,0"/>
          <Button x:Name="BtnWindows" Content="Más opciones en la configuración de Windows" Style="{DynamicResource Enlace}"/>
        </StackPanel>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
        <Button x:Name="BtnCerrar" Content="Cerrar" Margin="0,0,8,0"/>
        <Button x:Name="BtnLiberar" Content="Liberar" Style="{DynamicResource Primario}" MinWidth="150" IsEnabled="False"/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>
"@
function MostrarLiberarEspacio([switch]$Modal) {
    if ($script:opt -and $script:opt.Win -and $script:opt.Win.IsVisible) { [void]$script:opt.Win.Activate(); return }
    $w = NuevaVentana $XamlLiberar
    $script:opt = @{ Win = $w; Items = @(); Checks = @{}; Marcado = @{}; Timer = $null; Busq = $null; Letras = @(LetrasPorDefecto); Visto = -1 }
    PintarUnidades
    $w.FindName('BtnCerrar').add_Click({ $script:opt.Win.Close() })
    $w.FindName('BtnWindows').add_Click({ Start-Process 'ms-settings:storagesense' })
    $w.FindName('BtnExplorar').add_Click({ if (Get-Command MostrarExplorador -ErrorAction SilentlyContinue) { MostrarExplorador } })
    $w.FindName('BtnLiberar').add_Click({ LiberarSeleccion })
    $w.add_Closed({ $o = $script:opt; if ($o.Timer) { $o.Timer.Stop() }; PararBusquedaVentana })
    $script:opt.Timer = New-Object Windows.Threading.DispatcherTimer; $script:opt.Timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $script:opt.Timer.add_Tick({ RevisarBusquedaVentana })
    EmpezarBusquedaVentana
    if ($Modal) { [void]$w.ShowDialog() } else { MostrarSinBloquear $w }
}
# La ventana tiene su propia busqueda: va pintando lo que encuentra (lo rapido sale enseguida) y se rehace al cambiar de discos
function EmpezarBusquedaVentana {
    $o = $script:opt; PararBusquedaVentana
    $o.Items = @(); $o.Visto = -1
    $est = [hashtable]::Synchronized(@{ Paso = "Empezando..."; Frac = 0.0; Fin = $false; Ver = 0; Items = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList)) })
    if (-not $o.Letras.Count) { $est.Fin = $true; $o.Busq = @{ Estado = $est }; PintarOportunidades @(); return }
    $ps = [powershell]::Create()
    [void]$ps.AddScript({ param($config, $opt, $letras, $est) . $config; . $opt; try { [void](BuscarOportunidades $letras $est) } finally { $est.Fin = $true } }.ToString())
    [void]$ps.AddArgument((Join-Path $Codigo "config.ps1")); [void]$ps.AddArgument((Join-Path $Codigo "optimizar.ps1")); [void]$ps.AddArgument([string[]]$o.Letras); [void]$ps.AddArgument($est)
    $o.Busq = @{ PS = $ps; H = $ps.BeginInvoke(); Estado = $est }
    PintarOportunidades @()
    $o.Timer.Start()
}
function PararBusquedaVentana {
    $b = $script:opt.Busq; $script:opt.Busq = $null
    if ($b -and $b.PS) { try { [void]$b.PS.BeginStop($null, $null) } catch {} }   # sin esperar: se cierra sola
}
function RevisarBusquedaVentana {
    $o = $script:opt; if (-not $o.Busq) { $o.Timer.Stop(); return }
    $e = $o.Busq.Estado
    if ($e.Ver -ne $o.Visto) {
        $o.Visto = $e.Ver
        $o.Items = @($e.Items.ToArray() | Sort-Object { $_.Tipo -eq 'copiado' }, { -$_.Bytes })
        PintarOportunidades $o.Items
    } elseif ($o.Progreso) {
        $o.Progreso.Value = $e.Frac; $o.PasoTxt.Text = $e.Paso; $o.PctTxt.Text = "{0:N0} %" -f [math]::Floor($e.Frac * 100)
    }
    if ($e.Fin) {
        $o.Timer.Stop()
        if ($o.Busq.PS) { try { $o.Busq.PS.Dispose() } catch {} }
        $o.Busq.PS = $null
        PintarOportunidades $o.Items
    }
}
function Buscando { $b = $script:opt.Busq; return [bool]($b -and -not $b.Estado.Fin) }
function PintarUnidades {
    # Cada disco se puede marcar o desmarcar: solo se busca en los marcados. Los de backup van desmarcados de entrada.
    $u = $script:opt.Win.FindName('Unidades'); $u.Children.Clear()
    $backup = @(DiscosConectados | ForEach-Object { $_.Letra.ToUpper() })
    foreach ($d in @(EstadoUnidades)) {
        $l = $d.Letra.ToUpper(); $usado = $d.Total - $d.Libre
        $chk = New-Object Windows.Controls.CheckBox; $chk.IsChecked = $script:opt.Letras -contains $l; $chk.Tag = $l
        $chk.ToolTip = "Buscar en $l"
        $chk.add_Click({ param($s, $e) CambiarDiscoLiberar $s.Tag ([bool]$s.IsChecked) })
        $nombre = Texto "$l $($d.Etiqueta)" 13 'SemiBold'; $nombre.TextTrimming = 'CharacterEllipsis'
        $sub = if ($backup -contains $l) { "disco de copias  $([char]0x00B7)  $(TamTxt $d.Libre) libres" } else { "$(TamTxt $d.Libre) libres" }
        $c = Tarjeta (Apilar @((Fila @($chk, (Icono $GlifoDiscoDuro 18 $(if ($d.PocoEspacio) { 'Aviso' } else { 'Acento' })), $nombre) @('Auto', 'Auto', '*')),
                                 (Texto $sub 12 'Normal' $(if ($d.PocoEspacio) { 'Aviso' } else { 'Texto2' })),
                                 (BarraUso ($usado / [math]::Max(1.0, [double]$d.Total)) $(if ($d.PocoEspacio) { 'Aviso' } else { 'Acento' }))))
        $c.Child.Children[0].Children[1].Margin = '6,0,8,0'; $c.Child.Children[1].Margin = '0,4,0,0'; $c.Child.Children[2].Margin = '0,8,0,0'; $c.Margin = '0,0,8,0'
        $c.Opacity = if ($chk.IsChecked) { 1.0 } else { 0.6 }
        [void]$u.Children.Add($c)
    }
}
function CambiarDiscoLiberar($letra, [bool]$mirar) {
    $o = $script:opt
    $o.Letras = @(@($o.Letras | Where-Object { $_ -ne $letra }) + @(if ($mirar) { $letra }))
    # Se recuerda para la proxima vez
    $si = @(@(LeerAjuste 'LiberarMirar' @()) | Where-Object { $_ -ne $letra }); $no = @(@(LeerAjuste 'LiberarSinMirar' @()) | Where-Object { $_ -ne $letra })
    if ($mirar) { $si += $letra } else { $no += $letra }
    GuardarAjuste 'LiberarMirar' $si; GuardarAjuste 'LiberarSinMirar' $no
    PintarUnidades
    EmpezarBusquedaVentana
}
function PintarOportunidades($items) {
    $o = $script:opt; $o.Items = @($items); $l = $o.Win.FindName('Lista'); $l.Children.Clear(); $o.Checks = @{}; $o.Progreso = $null
    $buscando = Buscando
    if (-not $o.Items -and -not $buscando) {
        $txt = if ($o.Letras.Count) { "Todo en orden: no hay nada que merezca la pena borrar en $($o.Letras -join ', ')." } else { "Marca arriba los discos en los que quieres buscar." }
        [void]$l.Children.Add((Tarjeta (Fila @((Icono $GlifoOk 22 'Acento'), (Texto $txt 14 'SemiBold')) @('Auto', '*'))))
        ActualizarTotalLiberar; return
    }
    $cabecera = $false
    for ($k = 0; $k -lt $o.Items.Count; $k++) {
        $it = $o.Items[$k]
        if ($it.Tipo -eq 'copiado' -and -not $cabecera) {
            $cabecera = $true
            $h = Texto "Ya copiado en tus discos de backup" 16 'SemiBold'; $h.Margin = '2,16,0,2'; [void]$l.Children.Add($h)
            $x = Texto "Carpetas que llevan sin cambios desde su última copia. Si borras alguna del PC, antes se comprueba que la copia es idéntica (con el disco conectado) y se guarda aparte en el disco, en _ARCHIVO, para que no se pierda nunca. Revisa bien: después solo estará en el disco." 12 'Normal' 'Texto2'
            $x.Margin = '2,0,0,10'; [void]$l.Children.Add($x)
        }
        # Lo que el usuario marco o desmarco se respeta al repintar mientras sigue la busqueda
        $chk = New-Object Windows.Controls.CheckBox; $chk.IsChecked = $(if ($o.Marcado.ContainsKey($it.Id)) { $o.Marcado[$it.Id] } else { $it.Seguro }); $chk.Tag = $k
        $chk.add_Click({ param($s, $e) $script:opt.Marcado[$script:opt.Items[$s.Tag].Id] = [bool]$s.IsChecked; ActualizarTotalLiberar })
        $o.Checks[$k] = $chk
        $info = Apilar @((Texto $it.Titulo 14 'SemiBold'), (Texto $it.Detalle 12 'Normal' 'Texto2'))
        $info.Margin = '12,0,12,0'
        if ($it.Seguro) { $info.Children.Add((Chip "Seguro" 'acento')) | Out-Null; $info.Children[2].HorizontalAlignment = 'Left'; $info.Children[2].Margin = '0,6,0,0' }
        $ver = $null
        if ($it.Rutas) {
            $ver = New-Object Windows.Controls.Button; $ver.Style = $script:Estilos['Enlace']; $ver.Content = "Ver"; $ver.Tag = $k; $ver.Margin = '0,0,16,0'
            $ver.add_Click({ param($s, $e) VerOportunidad $script:opt.Items[$s.Tag] })
        }
        $tam = Texto (TamTxt $it.Bytes) 15 'SemiBold'; $tam.TextWrapping = 'NoWrap'
        [void]$l.Children.Add((Tarjeta (Fila @($chk, $info, $ver, $tam) @('Auto', '*', 'Auto', 'Auto'))))
    }
    if ($buscando) {
        # Sigue buscando: lo encontrado ya se puede marcar y liberar
        $e = $o.Busq.Estado
        $p = New-Object Windows.Controls.ProgressBar; $p.Height = 4; $p.Minimum = 0; $p.Maximum = 1; $p.Value = $e.Frac; $p.BorderThickness = 0; $p.Margin = '0,12,0,0'
        Recurso $p ([Windows.Controls.ProgressBar]::ForegroundProperty) 'Acento'; Recurso $p ([Windows.Controls.ProgressBar]::BackgroundProperty) 'Barra'
        $paso = Texto $e.Paso 12 'Normal' 'Texto2'
        $tit = if ($o.Items) { "Sigo buscando en $($o.Letras -join ', ')..." } else { "Buscando qué se puede liberar en $($o.Letras -join ', ')..." }
        $pct = Texto ("{0:N0} %" -f [math]::Floor($e.Frac * 100)) 15 'SemiBold' 'Acento'
        [void]$l.Children.Add((Tarjeta (Apilar @((Fila @((Texto $tit 15 'SemiBold'), $pct) @('*', 'Auto')), $paso, $p))))
        $o.Progreso = $p; $o.PasoTxt = $paso; $o.PctTxt = $pct
    }
    ActualizarTotalLiberar
}
function VerOportunidad($it) {
    # Una carpeta: se abre. Varios archivos: se abre la primera carpeta con el primero seleccionado.
    $r = $it.Rutas[0]
    if ($it.Id -like 'cache:*' -or $it.Id -eq 'temp') { Start-Process explorer.exe (Split-Path $r -Parent) }
    else { Start-Process explorer.exe "/select,`"$r`"" }
}
function ActualizarTotalLiberar {
    $o = $script:opt; $t = [int64]0
    foreach ($k in $o.Checks.Keys) { if ($o.Checks[$k].IsChecked) { $t += $o.Items[$k].Bytes } }
    $b = $o.Win.FindName('BtnLiberar'); $b.IsEnabled = $t -gt 0; $b.Content = if ($t -gt 0) { "Liberar $(TamTxt $t)" } else { "Liberar" }
    $o.Total = $t
}
function BorrarYaCopiada($it) {
    # Comprueba que la copia del disco es identica, la mueve a _ARCHIVO (asi el espejo de la proxima copia no la borra)
    # y solo entonces borra la carpeta del PC. Devuelve $true si se ha hecho.
    $c = DiscosConectados | Where-Object { $_.Id -eq $it.Disco } | Select-Object -First 1
    if (-not $c) { return $false }
    $src = $it.Rutas[0]; $dst = Join-Path $c.Raiz $it.Destino
    if (-not (Test-Path -LiteralPath $dst)) { return $false }
    $args2 = @("`"$src`"", "`"$dst`"", '/XD') + $Excluir + @('/MIR', '/L', '/FFT', '/XJ', '/R:0', '/W:0', '/NJH', '/NJS', '/NFL', '/NDL')
    $pi = New-Object Diagnostics.ProcessStartInfo 'robocopy.exe', ($args2 -join ' '); $pi.UseShellExecute = $false; $pi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($pi); while (-not $p.WaitForExit(150)) { [Windows.Forms.Application]::DoEvents() }
    if ($p.ExitCode -ne 0) { return $false }   # la copia no es identica: no se toca nada
    try {
        $arch = Join-Path $c.Raiz (Join-Path "_ARCHIVO" $it.Destino)
        New-Item -ItemType Directory -Path (Split-Path $arch -Parent) -Force | Out-Null
        if (Test-Path -LiteralPath $arch) { $arch += "_" + (Get-Date -Format "yyyyMMdd") }
        Move-Item -LiteralPath $dst -Destination $arch -ErrorAction Stop
    } catch { return $false }
    try { Remove-Item -LiteralPath $src -Recurse -Force -ErrorAction Stop } catch { return $false }
    $rep = LeerReparto; [void]$rep.Remove($src); GuardarReparto $rep
    [pscustomobject]@{ Fecha = (Get-Date -Format "yyyy-MM-dd"); Original = $src; Guardado_en = $arch; GB = [math]::Round($it.Bytes / 1GB, 2) } |
        Export-Csv -Path (Join-Path $c.Raiz "_ARCHIVO\indice_archivo.csv") -Append -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    return $true
}
function LiberarSeleccion {
    $o = $script:opt; $w = $o.Win
    $sel = @(foreach ($k in $o.Checks.Keys) { if ($o.Checks[$k].IsChecked) { $o.Items[$k] } })
    if (-not $sel) { return }
    $definitivo = [bool]$w.FindName('ModoBorrar').IsChecked
    # Lo que se regenera solo (temporales, caches, node_modules, previas) se borra siempre del todo: mandarlo a la
    # papelera no liberaria nada. El modo elegido se aplica a lo demas (Descargas).
    $regen = @($sel | Where-Object { $_.Id -eq 'temp' -or $_.Id -like 'cache:*' -or $_.Id -eq 'node_modules' -or $_.Id -eq 'lightroom' -or $_.Tipo -eq 'papelera' })
    $copiadas = @($sel | Where-Object { $_.Tipo -eq 'copiado' })
    $resto = @($sel | Where-Object { $regen -notcontains $_ -and $copiadas -notcontains $_ })
    if ($copiadas) {
        if ((Get-Command Copiando -ErrorAction SilentlyContinue) -and (Copiando)) { [void](Dialogo $w "Hay una copia en marcha" "Espera a que termine la copia de seguridad para borrar carpetas ya copiadas."); return }
        $faltan = @($copiadas | Where-Object { $id = $_.Disco; -not (DiscosConectados | Where-Object { $_.Id -eq $id }) } | ForEach-Object { $_.DiscoNombre } | Select-Object -Unique)
        if ($faltan) { [void](Dialogo $w "Conecta el disco de backup" "Para borrar del PC las carpetas ya copiadas hay que comprobar antes su copia. Conecta: $($faltan -join ', ')."); return }
    }
    $msg = ""
    if ($regen) { $msg += "Se borrarán del todo (se regeneran solos o ya estaban borrados):`n" + (($regen | ForEach-Object { "$([char]0x2022) $($_.Titulo) ($(TamTxt $_.Bytes))" }) -join "`n") }
    if ($copiadas) { $msg += $(if ($msg) { "`n`n" } else { "" }) + "Se borrarán del PC, después de comprobar que su copia es idéntica y guardarla aparte en el disco (_ARCHIVO):`n" + (($copiadas | ForEach-Object { "$([char]0x2022) $($_.Titulo) ($(TamTxt $_.Bytes)) $([char]0x2192) «$($_.DiscoNombre)»" }) -join "`n") }
    if ($resto) { $msg += $(if ($msg) { "`n`n" } else { "" }) + "$(if ($definitivo) { 'Se borrarán DEFINITIVAMENTE (no se pueden recuperar)' } else { 'Irán a la papelera (puedes recuperarlos desde allí)' }):`n" + (($resto | ForEach-Object { "$([char]0x2022) $($_.Titulo) ($(TamTxt $_.Bytes))" }) -join "`n") }
    if ((Dialogo $w "¿Liberar $(TamTxt $o.Total)?" $msg @('Cancelar', 'Liberar') 'Liberar') -ne 'Liberar') { return }
    $w.Cursor = [Windows.Input.Cursors]::Wait; $w.FindName('BtnLiberar').IsEnabled = $false
    $libre = @(EstadoUnidades | ForEach-Object { $_.Libre }) | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    $fallos = 0
    Add-Type -AssemblyName Microsoft.VisualBasic
    foreach ($it in $sel) {
        if ($it.Tipo -eq 'copiado') { if (-not (BorrarYaCopiada $it)) { $fallos++ }; continue }
        if ($it.Tipo -eq 'papelera') {
            # Solo la papelera de los discos elegidos
            foreach ($le in @(if ($it.Letras) { $it.Letras } else { $o.Letras })) { try { Clear-RecycleBin -DriveLetter $le.Substring(0, 1) -Force -ErrorAction Stop } catch { $fallos++ } }
            continue
        }
        $delTodo = $definitivo -or ($regen -contains $it)
        foreach ($r in $it.Rutas) {
            [Windows.Forms.Application]::DoEvents()
            try {
                $esDir = Test-Path -LiteralPath $r -PathType Container
                if ($delTodo) { Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction Stop }
                elseif ($esDir) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($r, 'OnlyErrorDialogs', 'SendToRecycleBin') }
                else { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($r, 'OnlyErrorDialogs', 'SendToRecycleBin') }
            } catch { $fallos++ }   # en uso o sin permiso: se deja
        }
    }
    $despues = @(EstadoUnidades | ForEach-Object { $_.Libre }) | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    $w.Cursor = $null
    $txt = "Has liberado $(TamTxt ([math]::Max(0.0, [double]($despues - $libre))))."
    if ($resto -and -not $definitivo) { $txt += " Lo de Descargas está en la papelera: ese espacio se libera del todo cuando la vacíes." }
    if ($fallos) { $txt += "`n`n$fallos elementos no se pudieron borrar porque estaban en uso. Cierra los programas y vuelve a intentarlo." }
    [void](Dialogo $w "Hecho" $txt)
    PintarUnidades
    $o.Marcado = @{}
    EmpezarBusquedaVentana
}

# Ejecutado suelto: abrir la ventana (para probar)
if ($MyInvocation.InvocationName -ne '.') {
    if (-not (Get-Command LeerCarpetas -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot "config.ps1") }
    if (-not (Get-Command NuevaVentana -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot "ui.ps1") }
    if (-not (Get-Command TamTxt -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot "asistente.ps1") }
    MostrarLiberarEspacio -Modal
}
