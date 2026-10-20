# ============================================================
#  Genera el logo de BackupApp: recursos\BackupApp.ico (16..256 px) y recursos\logo.png
#  Dos escudos superpuestos (el original y su copia) con una flecha de "guardar".
#  Uso: powershell -NoProfile -ExecutionPolicy Bypass -File herramientas\generar_icono.ps1
# ============================================================
Add-Type -AssemblyName System.Drawing
$raiz = Split-Path $PSScriptRoot -Parent
$dir  = Join-Path $raiz "recursos"
New-Item -ItemType Directory -Path $dir -Force | Out-Null

function Escudo($x, $y, $w, $h) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $p.AddBezier([single]$x, [single]($y + 0.12 * $h), [single]($x + 0.25 * $w), [single]($y + 0.10 * $h), [single]($x + 0.40 * $w), [single]$y, [single]($x + 0.5 * $w), [single]$y)
    $p.AddBezier([single]($x + 0.5 * $w), [single]$y, [single]($x + 0.60 * $w), [single]$y, [single]($x + 0.75 * $w), [single]($y + 0.10 * $h), [single]($x + $w), [single]($y + 0.12 * $h))
    $p.AddLine([single]($x + $w), [single]($y + 0.12 * $h), [single]($x + $w), [single]($y + 0.50 * $h))
    $p.AddBezier([single]($x + $w), [single]($y + 0.50 * $h), [single]($x + $w), [single]($y + 0.78 * $h), [single]($x + 0.72 * $w), [single]($y + 0.92 * $h), [single]($x + 0.5 * $w), [single]($y + $h))
    $p.AddBezier([single]($x + 0.5 * $w), [single]($y + $h), [single]($x + 0.28 * $w), [single]($y + 0.92 * $h), [single]$x, [single]($y + 0.78 * $h), [single]$x, [single]($y + 0.50 * $h))
    $p.CloseFigure()
    return $p
}
function Redondeado($x, $y, $w, $h, $r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function Dibujar([int]$n) {
    $bmp = New-Object Drawing.Bitmap $n, $n, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.Clear([Drawing.Color]::Transparent)
    $s = $n / 256.0
    $pequeno = $n -le 24

    # Fondo: cuadrado redondeado, verde azulado -> indigo
    $m = if ($pequeno) { 0 } else { 8 * $s }
    $fondo = Redondeado $m $m ($n - 2 * $m) ($n - 2 * $m) ([math]::Max(2, 56 * $s))
    $grad = New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.PointF 0, 0), (New-Object Drawing.PointF $n, $n),
        ([Drawing.Color]::FromArgb(255, 20, 184, 166)), ([Drawing.Color]::FromArgb(255, 49, 46, 129))
    $g.FillPath($grad, $fondo)

    # Escudo de atras (la copia), desplazado y translucido
    if (-not $pequeno) {
        $atras = Escudo (86 * $s) (34 * $s) (128 * $s) (160 * $s)
        $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(90, 255, 255, 255))), $atras)
    }
    # Escudo principal
    $ex = if ($pequeno) { 38 * $s } else { 50 * $s }; $ey = if ($pequeno) { 30 * $s } else { 62 * $s }
    $ew = if ($pequeno) { 180 * $s } else { 128 * $s }; $eh = if ($pequeno) { 200 * $s } else { 160 * $s }
    $g.FillPath([Drawing.Brushes]::White, (Escudo $ex $ey $ew $eh))

    # Flecha hacia abajo sobre una bandeja (guardar)
    $tinta = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 30, 64, 120))
    $cx = $ex + $ew / 2; $grosor = $ew * $(if ($pequeno) { 0.22 } else { 0.16 })
    $top = $ey + $eh * 0.20; $punta = $ey + $eh * 0.62
    $cab = $ew * $(if ($pequeno) { 0.30 } else { 0.24 })
    $g.FillRectangle($tinta, [single]($cx - $grosor / 2), [single]$top, [single]$grosor, [single]($punta - $top - $cab * 0.8))
    $tri = [Drawing.PointF[]]@((New-Object Drawing.PointF ($cx - $cab), ($punta - $cab)), (New-Object Drawing.PointF ($cx + $cab), ($punta - $cab)), (New-Object Drawing.PointF $cx, $punta))
    $g.FillPolygon($tinta, $tri)
    if (-not $pequeno) {
        $bw = $ew * 0.46; $bh = $ew * 0.07
        $g.FillRectangle($tinta, [single]($cx - $bw / 2), [single]($punta + $eh * 0.06), [single]$bw, [single]$bh)
    }
    $g.Dispose()
    return $bmp
}

# Imagen en formato DIB de 32 bits (lo que entienden todas las versiones de Windows y .NET)
function DibDe($bmp) {
    $n = $bmp.Width
    $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ms
    $w.Write([int32]40); $w.Write([int32]$n); $w.Write([int32]($n * 2)); $w.Write([int16]1); $w.Write([int16]32)
    $w.Write([int32]0); $w.Write([int32]0); $w.Write([int32]0); $w.Write([int32]0); $w.Write([int32]0); $w.Write([int32]0)
    for ($y = $n - 1; $y -ge 0; $y--) { for ($x = 0; $x -lt $n; $x++) { $c = $bmp.GetPixel($x, $y); $w.Write([byte]$c.B); $w.Write([byte]$c.G); $w.Write([byte]$c.R); $w.Write([byte]$c.A) } }
    $fila = [int]([math]::Ceiling($n / 32.0) * 4)
    $w.Write((New-Object byte[] ($fila * $n)))   # mascara AND vacia (la transparencia va en el canal alfa)
    $w.Flush(); return , $ms.ToArray()
}
function PngDe($bmp) { $ms = New-Object IO.MemoryStream; $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); return , $ms.ToArray() }

$tamanos = 16, 20, 24, 32, 40, 48, 64, 256
$imagenes = New-Object 'System.Collections.Generic.List[byte[]]'
foreach ($t in $tamanos) { $b = Dibujar $t; if ($t -ge 256) { $imagenes.Add((PngDe $b)) } else { $imagenes.Add((DibDe $b)) }; $b.Dispose() }

$ico = Join-Path $dir "BackupApp.ico"
$fs = [IO.File]::Create($ico); $w = New-Object IO.BinaryWriter $fs
$w.Write([int16]0); $w.Write([int16]1); $w.Write([int16]$tamanos.Count)
$offset = 6 + 16 * $tamanos.Count
for ($i = 0; $i -lt $tamanos.Count; $i++) {
    $t = $tamanos[$i]; $lado = if ($t -ge 256) { 0 } else { $t }
    $w.Write([byte]$lado); $w.Write([byte]$lado); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([int16]1); $w.Write([int16]32); $w.Write([int32]$imagenes[$i].Length); $w.Write([int32]$offset)
    $offset += $imagenes[$i].Length
}
foreach ($img in $imagenes) { $w.Write($img) }
$w.Close()

$grande = Dibujar 512; $grande.Save((Join-Path $dir "logo.png"), [Drawing.Imaging.ImageFormat]::Png); $grande.Dispose()
Write-Host "Creado: $ico"
