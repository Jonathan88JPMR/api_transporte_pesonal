# Genera los íconos PNG de la PWA replicando public/favicon.svg (bus azul)
Add-Type -AssemblyName System.Drawing

$blue  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0x15,0x65,0xC0))
$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$dark  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0x26,0x32,0x38))

function RoundedRect([System.Drawing.Graphics]$g, $brush, [float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = [Math]::Min($r * 2, [Math]::Min($w, $h))
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $g.FillPath($brush, $path)
    $path.Dispose()
}

function DrawBus([System.Drawing.Graphics]$g, [float]$ox, [float]$oy, [float]$s) {
    # $s = pixeles por unidad del viewBox 64x64, $ox/$oy = origen
    RoundedRect $g $white (15*$s+$ox) (12*$s+$oy) (34*$s) (37*$s) (5*$s)
    RoundedRect $g $blue  (19*$s+$ox) (17*$s+$oy) (26*$s) (13*$s) (2*$s)
    $g.FillRectangle($white, 30.5*$s+$ox, 17*$s+$oy, 3*$s, 13*$s)
    $g.FillEllipse($blue, (23-2.6)*$s+$ox, (39-2.6)*$s+$oy, 5.2*$s, 5.2*$s)
    $g.FillEllipse($blue, (41-2.6)*$s+$ox, (39-2.6)*$s+$oy, 5.2*$s, 5.2*$s)
    RoundedRect $g $blue (27*$s+$ox) (44*$s+$oy) (10*$s) (2.4*$s) (1.2*$s)
    RoundedRect $g $dark (18*$s+$ox) (49*$s+$oy) (9*$s) (6*$s) (2*$s)
    RoundedRect $g $dark (37*$s+$ox) (49*$s+$oy) (9*$s) (6*$s) (2*$s)
}

function New-Icon([int]$size, [bool]$maskable, [string]$out) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::FromArgb(0x15,0x65,0xC0))
    if ($maskable) {
        # safe zone: el bus ocupa el 72% central sobre fondo full-bleed
        $inner = $size * 0.72
        $pad = ($size - $inner) / 2
        DrawBus $g $pad $pad ($inner / 64.0)
    } else {
        $s = $size / 64.0
        RoundedRect $g $blue 0 0 $size $size (14 * $s)
        DrawBus $g 0 0 $s
    }
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Output "generado: $out"
}

$dir = "public/icons"
New-Icon 72  $false "$dir/icon-72.png"
New-Icon 180 $false "$dir/apple-touch-icon.png"
New-Icon 192 $false "$dir/icon-192.png"
New-Icon 512 $false "$dir/icon-512.png"
New-Icon 512 $true  "$dir/icon-maskable-512.png"
