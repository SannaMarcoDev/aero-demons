param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Destination
)
# Native Windows image composition only: no color correction or synthetic imagery.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
public static class HorizonDifference {
    public static double Mean(string first, string second, double heightFraction) {
        using (var a = new Bitmap(first))
        using (var b = new Bitmap(second)) {
            if (a.Size != b.Size) throw new Exception("Image sizes differ");
            double sum = 0; long samples = 0;
            // Sampling every fourth pixel; this is a repeatability check, not image quality.
            for (int y = 0; y < a.Height * heightFraction; y += 4)
                for (int x = 0; x < a.Width; x += 4) {
                    var p = a.GetPixel(x, y); var q = b.GetPixel(x, y);
                    sum += Math.Abs(p.R-q.R) + Math.Abs(p.G-q.G) + Math.Abs(p.B-q.B);
                    samples += 3;
                }
            return sum / samples / 255.0;
        }
    }
}
'@
$manifest = Get-Content -LiteralPath (Join-Path $Source 'manifest.json') -Raw | ConvertFrom-Json
if ($manifest.captures.Count -ne 10) { throw 'Expected two complete views with A/B/C/D/A_repeat' }
$metrics = @()
foreach ($altitude in @('12000', '19500')) {
    $captures = @($manifest.captures | Where-Object { $_.view.id -eq $altitude })
    if ($captures.Count -ne 5) { throw "Incomplete view $altitude" }
    foreach ($capture in $captures) {
        if ($capture.camera_transform -ne $captures[0].camera_transform -or $capture.player_transform -ne $captures[0].player_transform) {
            throw "Camera/aircraft changed within view $altitude"
        }
    }
    $a = Join-Path $Source ($altitude + '_A.png')
    $repeat = Join-Path $Source ($altitude + '_A_repeat.png')
    $background = [HorizonDifference]::Mean($a, $repeat, 0.55)
    if ($background -gt 0.002) { throw "A repeat has excessive history residue: $background" }
    $metrics += [pscustomobject]@{view=$altitude; a_repeat_background_mae=$background;
        a_repeat_full_frame_mae=[HorizonDifference]::Mean($a, $repeat, 1.0);
        a_b_full_frame_mae=[HorizonDifference]::Mean($a, (Join-Path $Source ($altitude + '_B.png')), 1.0);
        c_d_full_frame_mae=[HorizonDifference]::Mean((Join-Path $Source ($altitude + '_C.png')), (Join-Path $Source ($altitude + '_D.png')), 1.0)}
}
if (Test-Path -LiteralPath $Destination) { throw "Refusing to overwrite existing output: $Destination" }
$null = New-Item -ItemType Directory -Path $Destination
$Destination = (Resolve-Path -LiteralPath $Destination).Path
Copy-Item -LiteralPath (Join-Path $Source 'manifest.json') -Destination $Destination
foreach ($capture in $manifest.captures) {
    Copy-Item -LiteralPath (Join-Path $Source $capture.file) -Destination $Destination
}
$metrics | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Destination 'repeatability.json') -Encoding UTF8

$white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(237,243,251))
$muted = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(165,186,209))
$accent = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(104,202,238))
$panel = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(24,39,58))
$titleFont = [System.Drawing.Font]::new('Segoe UI', 34, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$labelFont = [System.Drawing.Font]::new('Segoe UI', 28, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$smallFont = [System.Drawing.Font]::new('Segoe UI', 22, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$labels = @('A  /  ATTUALE', 'B  /  FOSCHIA MORBIDA', 'C  /  SFUMATURA PIU MARCATA', 'D  /  C + BLUR LONTANO')

function Write-Sheet([string]$Altitude, [bool]$Crop) {
    $w = 1280; $h = 720
    if ($Crop) { $w = 880; $h = 380 }
    $margin = 20; $gap = 16; $header = 104; $label = 58
    $width = 2*$w + 2*$margin + $gap
    $height = $header + 2*($label+$h) + $gap + 60
    $sheet = [System.Drawing.Bitmap]::new($width, $height)
    $g = [System.Drawing.Graphics]::FromImage($sheet)
    try {
        $g.Clear([System.Drawing.Color]::FromArgb(12,22,35))
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawString('AERO DEMONS / CONFRONTO ORIZZONTE', $titleFont, $white, 20, 12)
        $viewLabel = if ($Altitude -eq '12000') { '12 km' } else { '19,5 km - quota diagnostica' }
        $subtitle = "Quota $viewLabel  |  Render reali Godot  |  A/B/C/D"
        if ($Crop) { $subtitle = 'Dettaglio orizzonte a 19,5 km | Stesso ritaglio, scala 1:1' }
        $g.DrawString($subtitle, $smallFont, $muted, 22, 60)
        for ($i=0; $i -lt 4; $i++) {
            $x = $margin + ($i % 2)*($w+$gap)
            $y = $header + [math]::Floor($i/2)*($label+$h+$gap)
            $g.FillRectangle($panel, $x, $y, $w, $label)
            $g.FillRectangle($accent, $x, $y, 5, $label)
            $g.DrawString($labels[$i], $labelFont, $white, $x+18, $y+10)
            $id = @('A','B','C','D')[$i]
            $image = [System.Drawing.Image]::FromFile((Join-Path $Source ($Altitude + '_' + $id + '.png')))
            try {
                $dest = [System.Drawing.Rectangle]::new($x, ($y+$label), $w, $h)
                $src = [System.Drawing.Rectangle]::new(0, 0, $image.Width, $image.Height)
                if ($Crop) { $src = [System.Drawing.Rectangle]::new(1030, 240, $w, $h) }
                $g.DrawImage($image, $dest, $src, [System.Drawing.GraphicsUnit]::Pixel)
            } finally { $image.Dispose() }
        }
        $g.DrawString('Stessa camera, luce e nuvole. Nessun ritocco colore. Produzione invariata.', $smallFont, $muted, 22, ($height-40))
        $name = if ($Crop) { 'collage-dettaglio.png' } else { "collage-$Altitude.png" }
        $sheet.Save((Join-Path $Destination $name), [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Output "Saved $Destination\$name"
    } finally { $g.Dispose(); $sheet.Dispose() }
}
try {
    Write-Sheet '12000' $false
    Write-Sheet '19500' $false
    Write-Sheet '19500' $true
} finally {
    foreach ($resource in @($white,$muted,$accent,$panel,$titleFont,$labelFont,$smallFont)) { $resource.Dispose() }
}
$metrics | Format-Table
Write-Output 'PASS: identical camera poses, stable A repeat, real captures assembled without recoloring'
