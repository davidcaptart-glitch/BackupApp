# ============================================================
#  INTERFAZ: estilo visual comun (WPF) con tema claro y oscuro
#  Lo usan el asistente, la ventana del plan y los dialogos. El menu del escudo (WinForms)
#  tambien toma de aqui sus colores.
#  Tema: ajuste "Tema" = sistema | claro | oscuro (en ajustes.json)
# ============================================================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, WindowsFormsIntegration
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

if (-not ("BackupApp.Dwm" -as [type])) {
    Add-Type -Namespace BackupApp -Name Dwm -MemberDefinition @'
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id);
'@
}
# Identificador de aplicacion: asi Windows agrupa las ventanas en la barra de tareas como "BackupApp" y con su icono,
# no como PowerShell. Los accesos directos del instalador llevan el mismo (instalador\BackupApp.iss).
$IdAplicacion = "davidcaptart.BackupApp"
[void][BackupApp.Dwm]::SetCurrentProcessExplicitAppUserModelID($IdAplicacion)
if (-not ("BackupApp.RenderMenu" -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System.Drawing;
using System.Windows.Forms;
namespace BackupApp {
    public class ColoresMenu : ProfessionalColorTable {
        public Color Fondo, Hover, Borde, Separador;
        public override Color ToolStripDropDownBackground { get { return Fondo; } }
        public override Color ImageMarginGradientBegin { get { return Fondo; } }
        public override Color ImageMarginGradientMiddle { get { return Fondo; } }
        public override Color ImageMarginGradientEnd { get { return Fondo; } }
        public override Color MenuBorder { get { return Borde; } }
        public override Color MenuItemBorder { get { return Hover; } }
        public override Color MenuItemSelected { get { return Hover; } }
        public override Color MenuItemSelectedGradientBegin { get { return Hover; } }
        public override Color MenuItemSelectedGradientEnd { get { return Hover; } }
        public override Color MenuItemPressedGradientBegin { get { return Hover; } }
        public override Color MenuItemPressedGradientEnd { get { return Hover; } }
        public override Color SeparatorDark { get { return Separador; } }
        public override Color SeparatorLight { get { return Fondo; } }
    }
    public class RenderMenu : ToolStripProfessionalRenderer {
        public Color Texto, TextoApagado;
        public RenderMenu(ColoresMenu c) : base(c) { RoundedEdges = true; }
        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) {
            e.TextColor = e.Item.Enabled ? Texto : TextoApagado; base.OnRenderItemText(e);
        }
        protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e) { e.ArrowColor = Texto; base.OnRenderArrow(e); }
    }
}
'@
}

$Temas = @{
    Claro  = @{ Fondo = '#F4F5F7'; Lateral = '#EBEDF0'; Tarjeta = '#FFFFFF'; TarjetaHover = '#F3F6F8'; Borde = '#E1E4E8'
                Texto = '#16191E'; Texto2 = '#606874'; Acento = '#0E8A7E'; AcentoHover = '#0B7369'; AcentoTexto = '#FFFFFF'
                AcentoSuave = '#DCF2EF'; Aviso = '#A85A06'; AvisoSuave = '#FDF1E1'; Barra = '#E4E7EB'; Scroll = '#C2C7CE' }
    Oscuro = @{ Fondo = '#15171B'; Lateral = '#1B1D22'; Tarjeta = '#212429'; TarjetaHover = '#292D33'; Borde = '#30343B'
                Texto = '#EDEFF2'; Texto2 = '#9AA2AD'; Acento = '#2EC4B2'; AcentoHover = '#4AD6C5'; AcentoTexto = '#062420'
                AcentoSuave = '#17392F'; Aviso = '#F2A84B'; AvisoSuave = '#3A2B16'; Barra = '#30343B'; Scroll = '#474E58' }
}

# ---------- Ajustes y tema ----------
function TemaActual {
    $t = LeerAjuste 'Tema' 'sistema'
    if ($t -eq 'claro') { return 'Claro' }
    if ($t -eq 'oscuro') { return 'Oscuro' }
    try { $v = Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop; if ($v -eq 0) { return 'Oscuro' } } catch {}
    return 'Claro'
}
function Pincel($hex) { $b = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($hex)); $b.Freeze(); return $b }
function BarraTituloOscura($win, [bool]$oscuro) {
    # Windows 10 (20H1+) y 11: barra de titulo a juego con el tema
    $h = (New-Object Windows.Interop.WindowInteropHelper $win).Handle
    if ($h -eq [IntPtr]::Zero) { return }
    $v = [int]$oscuro
    if ([BackupApp.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$v, 4) -ne 0) { [void][BackupApp.Dwm]::DwmSetWindowAttribute($h, 19, [ref]$v, 4) }
}
function AplicarTema($win, $nombre = (TemaActual)) {
    # (.psobject.BaseObject: WPF no acepta el envoltorio PSObject que PowerShell pone a los objetos)
    foreach ($k in $Temas[$nombre].Keys) { $win.Resources[$k] = (Pincel $Temas[$nombre][$k]).psobject.BaseObject }
    BarraTituloOscura $win ($nombre -eq 'Oscuro')
    $win.Tag = $nombre
}
function AplicarTemaATodas {
    # Al cambiar el tema se repintan todas las ventanas abiertas del programa
    foreach ($w in @($script:VentanasUI)) { if ($w.IsLoaded) { AplicarTema $w } }
}
$script:VentanasUI = New-Object 'System.Collections.Generic.List[object]'

function ColorDe($hex) { [Drawing.ColorTranslator]::FromHtml($hex) }
function EstiloMenu($menu) {
    # Menu del escudo (WinForms) con los colores del tema actual y esquinas redondeadas en Windows 11
    $t = $Temas[(TemaActual)]
    $c = New-Object BackupApp.ColoresMenu
    $c.Fondo = ColorDe $t.Tarjeta; $c.Hover = ColorDe $t.TarjetaHover; $c.Borde = ColorDe $t.Borde; $c.Separador = ColorDe $t.Borde
    $r = New-Object BackupApp.RenderMenu $c
    $r.Texto = ColorDe $t.Texto; $r.TextoApagado = ColorDe $t.Texto2
    $menu.Renderer = $r
    $menu.Font = New-Object Drawing.Font("Segoe UI", 10)
    $todos = @($menu)
    $pila = New-Object System.Collections.Stack; $pila.Push($menu)
    while ($pila.Count) { foreach ($it in $pila.Pop().Items) { if ($it -is [Windows.Forms.ToolStripMenuItem]) { $it.Padding = New-Object Windows.Forms.Padding 2, 5, 2, 5; if ($it.HasDropDownItems) { $it.DropDown.Renderer = $r; $todos += $it.DropDown; $pila.Push($it.DropDown) } } } }
    foreach ($m in $todos) { $v = 2; if ($m.Handle -ne [IntPtr]::Zero) { [void][BackupApp.Dwm]::DwmSetWindowAttribute($m.Handle, 33, [ref]$v, 4) } }
}

# ---------- Recursos ----------
function RutaRecurso($nombre) {
    # Instalado: junto al codigo. Desarrollo: carpeta recursos del repositorio.
    foreach ($r in @((Join-Path $Codigo $nombre), (Join-Path (Split-Path $Codigo -Parent) "recursos\$nombre"))) { if (Test-Path -LiteralPath $r) { return $r } }
    return $null
}
function ImagenDe($ruta) {
    if (-not $ruta) { return $null }
    $b = New-Object Windows.Media.Imaging.BitmapImage
    $b.BeginInit(); $b.UriSource = New-Object Uri $ruta; $b.CacheOption = 'OnLoad'; $b.EndInit(); $b.Freeze()
    return $b
}

# ---------- Estilos ----------
$EstilosXaml = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Style TargetType="Button">
    <Setter Property="Foreground" Value="{DynamicResource Texto}"/>
    <Setter Property="Background" Value="{DynamicResource Tarjeta}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Borde}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Padding" Value="18,8"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource TarjetaHover}"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="Primario" TargetType="Button">
    <Setter Property="Foreground" Value="{DynamicResource AcentoTexto}"/>
    <Setter Property="Background" Value="{DynamicResource Acento}"/>
    <Setter Property="Padding" Value="22,8"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource AcentoHover}"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="Enlace" TargetType="Button">
    <Setter Property="Foreground" Value="{DynamicResource Acento}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <TextBlock x:Name="t" Text="{TemplateBinding Content}" Background="Transparent"/>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="t" Property="TextDecorations" Value="Underline"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="CheckBox">
    <Setter Property="Foreground" Value="{DynamicResource Texto}"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <StackPanel Orientation="Horizontal" Background="Transparent">
            <Border x:Name="caja" Width="20" Height="20" CornerRadius="5" BorderThickness="1.5" BorderBrush="{DynamicResource Texto2}" Background="Transparent" VerticalAlignment="Center">
              <Path x:Name="marca" Data="M 3.5,9 L 7,12.5 L 13.5,5" Stroke="{DynamicResource AcentoTexto}" StrokeThickness="2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Visibility="Collapsed"/>
            </Border>
            <ContentPresenter Margin="10,0,0,0" VerticalAlignment="Center"/>
          </StackPanel>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="caja" Property="Background" Value="{DynamicResource Acento}"/>
              <Setter TargetName="caja" Property="BorderBrush" Value="{DynamicResource Acento}"/>
              <Setter TargetName="marca" Property="Visibility" Value="Visible"/>
            </Trigger>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="caja" Property="BorderBrush" Value="{DynamicResource Acento}"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.35"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="Pastilla" TargetType="RadioButton">
    <Setter Property="Foreground" Value="{DynamicResource Texto2}"/>
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="RadioButton">
          <Border x:Name="b" CornerRadius="13" Padding="11,4" Background="Transparent" Margin="1,0">
            <ContentPresenter HorizontalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource TarjetaHover}"/></Trigger>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="b" Property="Background" Value="{DynamicResource AcentoSuave}"/>
              <Setter Property="Foreground" Value="{DynamicResource Acento}"/>
              <Setter Property="FontWeight" Value="SemiBold"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="TextBox">
    <Setter Property="Foreground" Value="{DynamicResource Texto}"/>
    <Setter Property="Background" Value="{DynamicResource Fondo}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Borde}"/>
    <Setter Property="CaretBrush" Value="{DynamicResource Texto}"/>
    <Setter Property="Padding" Value="8,6"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="TextBox">
          <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="6">
            <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource Acento}"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="PasswordBox">
    <Setter Property="Foreground" Value="{DynamicResource Texto}"/>
    <Setter Property="Background" Value="{DynamicResource Fondo}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Borde}"/>
    <Setter Property="CaretBrush" Value="{DynamicResource Texto}"/>
    <Setter Property="Padding" Value="8,6"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="PasswordBox">
          <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="6">
            <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource Acento}"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style TargetType="ScrollBar">
    <Setter Property="Width" Value="8"/>
    <Setter Property="MinWidth" Value="8"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ScrollBar">
          <Track x:Name="PART_Track" IsDirectionReversed="True">
            <Track.Thumb>
              <Thumb>
                <Thumb.Template>
                  <ControlTemplate TargetType="Thumb"><Border CornerRadius="4" Background="{DynamicResource Scroll}" Margin="1,2"/></ControlTemplate>
                </Thumb.Template>
              </Thumb>
            </Track.Thumb>
          </Track>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
</ResourceDictionary>
'@
$script:Estilos = $null
function NuevaVentana($xaml) {
    # Crea una ventana desde XAML con los estilos y el tema del programa
    $w = [Windows.Markup.XamlReader]::Parse($xaml)
    if (-not $script:Estilos) { $script:Estilos = [Windows.Markup.XamlReader]::Parse($EstilosXaml) }
    $w.Resources.MergedDictionaries.Add($script:Estilos)
    AplicarTema $w
    # El icono se carga en memoria (OnLoad): si se leyera del archivo, quedaria abierto y el instalador no podria actualizarlo
    $ico = RutaRecurso "BackupApp.ico"; if ($ico) { try { $w.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri $ico), [Windows.Media.Imaging.BitmapCreateOptions]::None, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad) } catch {} }
    $w.add_SourceInitialized({ param($s, $e) BarraTituloOscura $s ($s.Tag -eq 'Oscuro') })
    $w.add_Closed({ param($s, $e) [void]$script:VentanasUI.Remove($s) })
    $script:VentanasUI.Add($w)
    return $w
}
function MostrarSinBloquear($w) {
    # En el icono (principal.ps1 cargado) todas las pantallas se muestran dentro de la ventana principal
    if ((Get-Command MostrarVista -ErrorAction SilentlyContinue) -and -not ($script:Principal -and $w -eq $script:Principal.Win)) { MostrarVista $w; return }
    MostrarVentanaReal $w
}
function MostrarVentanaReal($w) {
    # Ventana WPF dentro del bucle de mensajes de WinForms (icono de la bandeja): necesita esto para el teclado
    [Windows.Forms.Integration.ElementHost]::EnableModelessKeyboardInterop($w)
    $w.Show(); [void]$w.Activate()
}
function VentanaAbierta($w) {
    # Una pantalla esta abierta si se ve como ventana o si esta dentro de la ventana principal
    if (-not $w) { return $false }
    if ($w.IsVisible) { return $true }
    return [bool]($script:Principal -and @($script:Principal.Vistas.Values | Where-Object { $_.Win -eq $w }).Count)
}
function DuenoVisible($d) {
    # Un dialogo necesita como dueno una ventana que se vea: las pantallas de dentro de la principal no se ven por si solas
    if ($d -and $d.IsVisible) { return $d }
    if ($script:Principal -and $script:Principal.Win.IsVisible) { return $script:Principal.Win }
    return $null
}
$VentanaBase = 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Background="{DynamicResource Fondo}" Foreground="{DynamicResource Texto}" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display"'

# ---------- Piezas para construir pantallas desde codigo ----------
function Recurso($el, $prop, $clave) { $el.SetResourceReference($prop, $clave) }
function Texto($txt, $tam = 13, $peso = 'Normal', $clave = 'Texto') {
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $txt; $t.FontSize = $tam; $t.FontWeight = $peso; $t.TextWrapping = 'Wrap'
    Recurso $t ([Windows.Controls.TextBlock]::ForegroundProperty) $clave
    return $t
}
function Tarjeta($hijo, $fondo = 'Tarjeta', $borde = 'Borde') {
    $b = New-Object Windows.Controls.Border; $b.CornerRadius = 8; $b.BorderThickness = 1; $b.Padding = '16,12'; $b.Margin = '0,0,0,8'
    Recurso $b ([Windows.Controls.Border]::BackgroundProperty) $fondo; Recurso $b ([Windows.Controls.Border]::BorderBrushProperty) $borde
    $b.Child = $hijo
    return $b
}
function Chip($txt, $tipo = 'normal') {
    # Etiqueta pequena: normal, acento o aviso
    $b = New-Object Windows.Controls.Border; $b.CornerRadius = 10; $b.Padding = '8,2'; $b.Margin = '0,0,6,0'
    $f, $c = switch ($tipo) { 'acento' { 'AcentoSuave', 'Acento' } 'aviso' { 'AvisoSuave', 'Aviso' } default { 'Fondo', 'Texto2' } }
    Recurso $b ([Windows.Controls.Border]::BackgroundProperty) $f
    $b.Child = Texto $txt 11 'SemiBold' $c
    return $b
}
function Icono($glifo, $tam = 20, $clave = 'Texto2') {
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $glifo; $t.FontSize = $tam
    $t.FontFamily = New-Object Windows.Media.FontFamily "Segoe Fluent Icons, Segoe MDL2 Assets"
    Recurso $t ([Windows.Controls.TextBlock]::ForegroundProperty) $clave
    return $t
}
function BarraUso([double]$fraccion, $clave = 'Acento') {
    # Barra de progreso fina y redondeada (0..1)
    $g = New-Object Windows.Controls.Grid; $g.Height = 6
    $fondo = New-Object Windows.Controls.Border; $fondo.CornerRadius = 3; Recurso $fondo ([Windows.Controls.Border]::BackgroundProperty) 'Barra'
    $f = [math]::Max(0.0, [math]::Min(1.0, [double]$fraccion))
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = New-Object Windows.GridLength ([math]::Max($f, 0.0001)), 'Star'
    $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = New-Object Windows.GridLength ([math]::Max(1 - $f, 0.0001)), 'Star'
    $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
    $lleno = New-Object Windows.Controls.Border; $lleno.CornerRadius = 3; Recurso $lleno ([Windows.Controls.Border]::BackgroundProperty) $clave
    [Windows.Controls.Grid]::SetColumnSpan($fondo, 2)
    [void]$g.Children.Add($fondo); [void]$g.Children.Add($lleno)
    return $g
}
function Fila($elementos, $anchos) {
    # Grid de una fila; $anchos: 'Auto', '*', o un numero
    $g = New-Object Windows.Controls.Grid
    for ($i = 0; $i -lt $elementos.Count; $i++) {
        $c = New-Object Windows.Controls.ColumnDefinition
        $c.Width = switch ($anchos[$i]) { 'Auto' { [Windows.GridLength]::Auto } '*' { New-Object Windows.GridLength 1, 'Star' } default { New-Object Windows.GridLength ([double]$_) } }
        $g.ColumnDefinitions.Add($c)
        if ($elementos[$i]) { [Windows.Controls.Grid]::SetColumn($elementos[$i], $i); $elementos[$i].VerticalAlignment = 'Center'; [void]$g.Children.Add($elementos[$i]) }
    }
    return $g
}
function Apilar($elementos, $horizontal = $false) {
    $s = New-Object Windows.Controls.StackPanel; if ($horizontal) { $s.Orientation = 'Horizontal' }
    foreach ($e in $elementos) { if ($e) { [void]$s.Children.Add($e) } }
    return $s
}

# ---------- Selector de carpetas moderno (el de Windows Vista y posteriores) ----------
if (-not ("BackupApp.SelectorCarpeta" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace BackupApp {
    public static class SelectorCarpeta {
        [ComImport, Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")] class FileOpenDialogRCW { }
        [ComImport, Guid("42f85136-db7e-439c-85f1-e4075d135fc8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IFileOpenDialog {
            [PreserveSig] int Show(IntPtr parent);
            void SetFileTypes(); void SetFileTypeIndex(); void GetFileTypeIndex(); void Advise(); void Unadvise();
            void SetOptions(uint fos); void GetOptions(out uint fos);
            void SetDefaultFolder(); void SetFolder(); void GetFolder(); void GetCurrentSelection();
            void SetFileName(); void GetFileName();
            void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
            void SetOkButtonLabel(); void SetFileNameLabel();
            void GetResult(out IShellItem item);
        }
        [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IShellItem { void BindToHandler(); void GetParent(); void GetDisplayName(uint sigdn, [MarshalAs(UnmanagedType.LPWStr)] out string name); }
        public static string Elegir(IntPtr owner, string titulo) {
            IFileOpenDialog d = (IFileOpenDialog)new FileOpenDialogRCW();
            uint op; d.GetOptions(out op);
            d.SetOptions(op | 0x20 | 0x40);   // FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM
            d.SetTitle(titulo);
            if (d.Show(owner) != 0) return null;
            IShellItem it; d.GetResult(out it);
            string p; it.GetDisplayName(0x80058000, out p);   // SIGDN_FILESYSPATH
            return p;
        }
    }
}
'@
}
function ElegirCarpeta($dueno, $titulo) {
    $h = if ($dueno) { (New-Object Windows.Interop.WindowInteropHelper $dueno).Handle } else { [IntPtr]::Zero }
    try { return [BackupApp.SelectorCarpeta]::Elegir($h, $titulo) } catch { return $null }
}

# ---------- Dialogos ----------
function Dialogo($dueno, $titulo, $texto, $botones = @('Aceptar'), $primario = $null, $conEntrada = $null) {
    # Devuelve el texto del boton pulsado (o $null si se cierra). Con $conEntrada muestra una caja de texto
    # con ese valor inicial y deja lo escrito en $script:EntradaDialogo.
    # Modo de prueba ($env:BACKUPAPP_PRUEBA): no muestra nada, escribe el texto y responde con la opcion principal.
    if ($env:BACKUPAPP_PRUEBA) {
        $r = if ($primario) { $primario } else { $botones[-1] }
        [Console]::WriteLine("[DIALOGO] $titulo | $($texto -replace "`n", ' / ') -> $r")
        $script:EntradaDialogo = $conEntrada; return $r
    }
    $w = NuevaVentana "<Window $VentanaBase Title=""BackupApp"" SizeToContent=""Height"" Width=""460"" ResizeMode=""NoResize"" WindowStartupLocation=""CenterOwner"" ShowInTaskbar=""False""><StackPanel Margin=""24,22,24,20""><TextBlock x:Name=""T"" FontSize=""18"" FontWeight=""SemiBold"" TextWrapping=""Wrap""/><TextBlock x:Name=""X"" Margin=""0,10,0,0"" TextWrapping=""Wrap"" Foreground=""{DynamicResource Texto2}""/><TextBox x:Name=""E"" Margin=""0,14,0,0"" Visibility=""Collapsed""/><StackPanel x:Name=""B"" Orientation=""Horizontal"" HorizontalAlignment=""Right"" Margin=""0,22,0,0""/></StackPanel></Window>"
    $dueno = DuenoVisible $dueno
    if ($dueno) { try { $w.Owner = $dueno } catch { $w.WindowStartupLocation = 'CenterScreen' } } else { $w.WindowStartupLocation = 'CenterScreen'; $w.Topmost = $true }
    $w.FindName('T').Text = $titulo; $w.FindName('X').Text = $texto
    $e = $w.FindName('E'); if ($null -ne $conEntrada) { $e.Visibility = 'Visible'; $e.Text = $conEntrada; $e.SelectAll(); [void]$e.Focus() }
    $script:RespuestaDialogo = $null
    foreach ($b in $botones) {
        $btn = New-Object Windows.Controls.Button; $btn.Content = $b; $btn.Margin = '8,0,0,0'; $btn.Tag = $b
        if ($b -eq $primario -or ($botones.Count -eq 1)) { $btn.Style = $w.FindResource('Primario'); $btn.IsDefault = $true }
        $btn.add_Click({ param($s, $ev) $script:RespuestaDialogo = $s.Tag; [Windows.Window]::GetWindow($s).Close() })
        [void]$w.FindName('B').Children.Add($btn)
    }
    [void]$w.ShowDialog()
    if ($null -ne $conEntrada) { $script:EntradaDialogo = $e.Text }
    return $script:RespuestaDialogo
}

function PreguntarNombreDisco($dueno, $actual, $letra) {
    # Pide un nombre para un disco de backup y, si esta conectado, ofrece ponerlo tambien como etiqueta de Windows
    $r = Dialogo $dueno "Nombre del disco" "Un nombre para reconocerlo, por ejemplo «Disco duro fotos». Te conviene escribirlo también en una pegatina." @('Cancelar', 'Guardar') 'Guardar' $actual
    if ($r -ne 'Guardar') { return $null }
    $n = "$script:EntradaDialogo".Trim()
    if (-not $n) { return $null }
    if ($letra) {
        $q = Dialogo $dueno "¿Cambiar también la etiqueta en Windows?" "Así el disco aparecerá como «$n» en el Explorador de archivos, en este PC y en cualquier otro. Windows pedirá permiso de administrador." @('Solo en BackupApp', 'También en Windows') 'También en Windows'
        if ($q -eq 'También en Windows' -and -not (CambiarEtiquetaWindows $letra $n)) {
            [void](Dialogo $dueno "No se cambió la etiqueta" "Windows no dejó cambiar la etiqueta del disco (quizá no se dio permiso). El nombre sí se usa en BackupApp.")
        }
    }
    return $n
}