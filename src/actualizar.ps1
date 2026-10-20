# ============================================================
#  ACTUALIZACIONES desde GitHub Releases ($RepoGitHub en config.ps1)
#  Cada release lleva BackupApp-setup-X.exe y BackupApp-setup-X.exe.sha256.
#  Se busca una vez al dia en segundo plano (y desde el menu). Antes de instalar se muestran las novedades
#  (las notas de la release, que salen de CHANGELOG.md). Al aceptar: se descarga, se comprueba el SHA-256
#  y se ejecuta el instalador en modo silencioso, que cierra el icono, sustituye el codigo y lo vuelve a abrir.
#  Pruebas sin GitHub: $env:BACKUPAPP_RELEASES = "file:///C:/ruta/release.json"
# ============================================================
$UrlUltimaRelease = if ($env:BACKUPAPP_RELEASES) { $env:BACKUPAPP_RELEASES } else { "https://api.github.com/repos/$RepoGitHub/releases/latest" }
$CarpetaDescarga = Join-Path $env:TEMP "BackupApp-actualizacion"

function LeerRelease {
    # Ultima release publicada, o $null si no hay ninguna valida. Lanza error si no hay conexion.
    if ($UrlUltimaRelease -like 'file:*') { $r = [IO.File]::ReadAllText(([uri]$UrlUltimaRelease).LocalPath) | ConvertFrom-Json }
    else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $r = Invoke-RestMethod -Uri $UrlUltimaRelease -UseBasicParsing -TimeoutSec 20 -Headers @{ 'User-Agent' = "BackupApp/$Version"; 'Accept' = 'application/vnd.github+json' }
    }
    $setup = $r.assets | Where-Object { $_.name -like 'BackupApp-setup-*.exe' } | Select-Object -First 1
    $hash  = $r.assets | Where-Object { $_.name -like 'BackupApp-setup-*.sha256' } | Select-Object -First 1
    if (-not $setup -or -not $hash -or $r.draft -or $r.prerelease) { return $null }
    [pscustomobject]@{ Version = "$($r.tag_name)".TrimStart('v', 'V'); Titulo = $r.name; Notas = "$($r.body)"; Fecha = $r.published_at
                       UrlSetup = $setup.browser_download_url; NombreSetup = $setup.name; Tamano = [int64]$setup.size; UrlHash = $hash.browser_download_url }
}
function EsMasNueva($v) { try { return ([version]$v -gt [version]$Version) } catch { return $false } }

# ---------- Busqueda en segundo plano ----------
function BuscarEnSegundoPlano {
    if ($script:busqueda) { return }
    $ps = [powershell]::Create()
    [void]$ps.AddScript({
        param($config, $act, $url)
        if ($url) { $env:BACKUPAPP_RELEASES = $url }
        . $config; . $act
        try { [pscustomobject]@{ Ok = $true; Release = (LeerRelease); Error = $null } }
        catch { [pscustomobject]@{ Ok = $false; Release = $null; Error = $_.Exception.Message } }
    }.ToString())
    [void]$ps.AddArgument((Join-Path $Codigo "config.ps1")); [void]$ps.AddArgument((Join-Path $Codigo "actualizar.ps1")); [void]$ps.AddArgument($env:BACKUPAPP_RELEASES)
    $script:busqueda = @{ PS = $ps; H = $ps.BeginInvoke() }
}
function ResultadoBusqueda {
    # $null mientras sigue buscando; despues, un objeto con Ok, Release y Error
    if (-not $script:busqueda -or -not $script:busqueda.H.IsCompleted) { return $null }
    try { $r = @($script:busqueda.PS.EndInvoke($script:busqueda.H)) | Select-Object -First 1 } catch { $r = [pscustomobject]@{ Ok = $false; Release = $null; Error = $_.Exception.Message } }
    $script:busqueda.PS.Dispose(); $script:busqueda = $null
    return $r
}

# ---------- Ventana de novedades ----------
$XamlNovedades = @"
<Window $VentanaBase Title="Actualización de BackupApp" Width="640" Height="620" MinWidth="520" MinHeight="420" WindowStartupLocation="CenterScreen">
  <Grid Margin="32,28,32,24">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Orientation="Horizontal">
      <Image x:Name="Logo" Width="44" Height="44"/>
      <StackPanel Margin="14,0,0,0" VerticalAlignment="Center">
        <TextBlock x:Name="Titulo" FontSize="24" FontWeight="SemiBold" FontFamily="Segoe UI Variable Display, Segoe UI"/>
        <TextBlock x:Name="Sub" Foreground="{DynamicResource Texto2}" TextWrapping="Wrap" MaxWidth="480"/>
      </StackPanel>
    </StackPanel>
    <TextBlock Grid.Row="1" Text="Novedades" FontSize="13" FontWeight="SemiBold" Foreground="{DynamicResource Texto2}" Margin="2,24,0,8"/>
    <Border Grid.Row="2" Background="{DynamicResource Tarjeta}" BorderBrush="{DynamicResource Borde}" BorderThickness="1" CornerRadius="8">
      <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="18,14,10,14"><StackPanel x:Name="Notas"/></ScrollViewer>
    </Border>
    <StackPanel x:Name="Progreso" Grid.Row="3" Margin="0,16,0,0" Visibility="Collapsed">
      <TextBlock x:Name="TxtProgreso" Foreground="{DynamicResource Texto2}" Margin="0,0,0,8"/>
      <ProgressBar x:Name="Barra" Height="6" Minimum="0" Maximum="1" BorderThickness="0" Foreground="{DynamicResource Acento}" Background="{DynamicResource Barra}"/>
    </StackPanel>
    <DockPanel Grid.Row="4" Margin="0,20,0,0">
      <Button x:Name="BtnOmitir" Content="Omitir esta versión" Style="{DynamicResource Enlace}" VerticalAlignment="Center"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="BtnLuego" Content="Más tarde" Margin="0,0,8,0"/>
        <Button x:Name="BtnInstalar" Content="Instalar ahora" Style="{DynamicResource Primario}" MinWidth="130"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@
function PintarNotas($panel, $md) {
    # Markdown sencillo de CHANGELOG.md: titulos (#), vinetas (- o *) y parrafos
    $panel.Children.Clear()
    foreach ($l in ($md -split "`r?`n")) {
        $x = $l.Trim() -replace '\*\*(.+?)\*\*', '$1' -replace '`(.+?)`', '$1'
        if (-not $x) { continue }
        if ($x -match '^#+\s*(.+)$') { $t = Texto $Matches[1] 15 'SemiBold'; $t.Margin = '0,8,0,4'; [void]$panel.Children.Add($t) }
        elseif ($x -match '^[-*]\s+(.+)$') {
            $f = Fila @((Texto ([string][char]0x2022) 13 'Bold' 'Acento'), (Texto $Matches[1] 13)) @('Auto', '*')
            $f.Children[0].VerticalAlignment = 'Top'; $f.Children[1].Margin = '10,0,0,0'; $f.Margin = '0,3,0,3'
            [void]$panel.Children.Add($f)
        }
        else { $t = Texto $x 13; $t.Margin = '0,3,0,3'; [void]$panel.Children.Add($t) }
    }
    if (-not $panel.Children.Count) { [void]$panel.Children.Add((Texto "Esta versión no incluye notas." 13 'Normal' 'Texto2')) }
}
function MostrarNovedades($rel, [switch]$Modal) {
    $w = NuevaVentana $XamlNovedades
    $script:act = @{ Win = $w; Rel = $rel; Ps = $null; H = $null; Destino = $null; Timer = $null }
    $w.FindName('Logo').Source = ImagenDe (RutaRecurso "logo.png")
    $w.FindName('Titulo').Text = "BackupApp $($rel.Version) ya está disponible"
    $fecha = try { " $([char]0x00B7) publicada el $(([datetime]$rel.Fecha).ToString('dd/MM/yyyy'))" } catch { "" }
    $w.FindName('Sub').Text = "Tienes la versión $Version$fecha. Tus datos y tu configuración no se tocan."
    PintarNotas $w.FindName('Notas') $rel.Notas
    $w.FindName('BtnLuego').add_Click({ $script:act.Win.Close() })
    $w.FindName('BtnOmitir').add_Click({ GuardarAjuste 'OmitirVersion' $script:act.Rel.Version; $script:act.Win.Close() })
    $w.FindName('BtnInstalar').add_Click({ DescargarEInstalar })
    $w.add_Closed({ $a = $script:act; if ($a.Timer) { $a.Timer.Stop() }; if ($a.Ps) { try { $a.Ps.Stop(); $a.Ps.Dispose() } catch {} } })
    if ($Modal) { [void]$w.ShowDialog() } else { MostrarSinBloquear $w }
}
function DescargarEInstalar {
    $a = $script:act; $w = $a.Win
    if ((Get-Command Copiando -ErrorAction SilentlyContinue) -and (Copiando)) {
        [void](Dialogo $w "Hay una copia en marcha" "Espera a que termine la copia de seguridad y vuelve a intentarlo."); return
    }
    foreach ($n in 'BtnInstalar', 'BtnLuego', 'BtnOmitir') { $w.FindName($n).IsEnabled = $false }
    $w.FindName('Progreso').Visibility = 'Visible'
    New-Item -ItemType Directory -Path $CarpetaDescarga -Force | Out-Null
    $a.Destino = Join-Path $CarpetaDescarga $a.Rel.NombreSetup
    foreach ($f in @($a.Destino, "$($a.Destino).sha256")) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
    # La descarga va en otro hilo; el temporizador mira cuanto lleva el archivo
    $ps = [powershell]::Create()
    [void]$ps.AddScript({
        param($url, $destino, $urlHash)
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $wc = New-Object Net.WebClient; $wc.Headers['User-Agent'] = 'BackupApp'
        $wc.DownloadFile($urlHash, "$destino.sha256")
        $wc.DownloadFile($url, $destino)
    }.ToString())
    [void]$ps.AddArgument($a.Rel.UrlSetup); [void]$ps.AddArgument($a.Destino); [void]$ps.AddArgument($a.Rel.UrlHash)
    $a.Ps = $ps; $a.H = $ps.BeginInvoke()
    $a.Timer = New-Object Windows.Threading.DispatcherTimer; $a.Timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $a.Timer.add_Tick({ SeguirDescarga })
    $a.Timer.Start()
}
function SeguirDescarga {
    $a = $script:act; $w = $a.Win
    $hecho = if (Test-Path -LiteralPath $a.Destino) { (Get-Item -LiteralPath $a.Destino).Length } else { 0 }
    $total = [math]::Max(1.0, [double]$a.Rel.Tamano)
    $w.FindName('Barra').Value = [math]::Min(1.0, $hecho / $total)
    $w.FindName('TxtProgreso').Text = "Descargando... $([math]::Round($hecho / 1MB, 1)) de $([math]::Round($total / 1MB, 1)) MB"
    if (-not $a.H.IsCompleted) { return }
    $a.Timer.Stop()
    $err = $null
    try { [void]$a.Ps.EndInvoke($a.H); if ($a.Ps.HadErrors) { $err = "$($a.Ps.Streams.Error[0])" } } catch { $err = $_.Exception.InnerException.Message; if (-not $err) { $err = $_.Exception.Message } }
    $a.Ps.Dispose(); $a.Ps = $null
    if (-not $err) { $err = ComprobarHash $a.Destino }
    if ($err) {
        [void](Dialogo $w "No se pudo actualizar" "$err`n`nNo se ha cambiado nada. Puedes volver a intentarlo más tarde.")
        foreach ($f in @($a.Destino, "$($a.Destino).sha256")) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
        $w.Close(); return
    }
    $w.FindName('Barra').Value = 1
    $w.FindName('TxtProgreso').Text = "Instalando la versión $($a.Rel.Version). BackupApp se cerrará y se volverá a abrir solo."
    if ($a.SoloProbar) { return }
    Start-Process -FilePath $a.Destino -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
    # El instalador espera a que el icono se cierre: salimos ya guardando los cambios pendientes
    if (Get-Command Salir -ErrorAction SilentlyContinue) { $w.Close(); Salir }
}
function ComprobarHash($archivo) {
    # Devuelve $null si el SHA-256 del instalador coincide con el publicado, o el motivo del error
    $esperado = (([IO.File]::ReadAllText("$archivo.sha256")).Trim() -split '\s+')[0].ToLower()
    if ($esperado -notmatch '^[0-9a-f]{64}$') { return "El archivo de comprobación de la descarga no es válido." }
    $real = (Get-FileHash -LiteralPath $archivo -Algorithm SHA256).Hash.ToLower()
    if ($real -ne $esperado) { return "La descarga está dañada o no es la original (el código SHA-256 no coincide)." }
    return $null
}
