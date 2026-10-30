# Regenerates the placeholder app icon and the bundled alarm tones.
# Run from the repo root on Windows:  pwsh tools/generate-assets.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# ---------- App icon (1024x1024, opaque) ----------
Add-Type -AssemblyName System.Drawing
$size = 1024
$bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$rect = New-Object System.Drawing.Rectangle 0, 0, $size, $size
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(94, 107, 230)), ([System.Drawing.Color]::FromArgb(48, 196, 190)), 45.0
$g.FillRectangle($bg, $rect)

# soft glow
$glow = New-Object System.Drawing.Drawing2D.GraphicsPath
$glow.AddEllipse(160, 120, 700, 700)
$pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush $glow
$pgb.CenterColor = [System.Drawing.Color]::FromArgb(90, 255, 255, 255)
$pgb.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 255, 255, 255))
$g.FillPath($pgb, $glow)

# capsule pill, rotated
$g.TranslateTransform(512, 512)
$g.RotateTransform(-45)
$w = 640; $h = 260; $r = $h / 2
function New-Capsule([float]$x, [float]$y, [float]$w, [float]$h) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $rr = $h / 2
    $p.AddArc($x, $y, $h, $h, 90, 180)
    $p.AddArc($x + $w - $h, $y, $h, $h, 270, 180)
    $p.CloseFigure()
    return $p
}
$shadow = New-Capsule (-$w / 2 + 14) (-$h / 2 + 22) $w $h
$g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(60, 0, 0, 40))), $shadow)
$pill = New-Capsule (-$w / 2) (-$h / 2) $w $h
$g.SetClip($pill)
$g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(250, 250, 255))), -$w / 2, -$h / 2, $w / 2, $h)
$g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 94, 120))), 0, -$h / 2, $w / 2, $h)
# glossy highlight
$g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70, 255, 255, 255))), -$w / 2, -$h / 2, $w, $h * 0.32)
$g.ResetClip()
$g.DrawPath((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(40, 0, 0, 0)), 4), $pill)
$g.Dispose()
$iconPath = Join-Path $root 'PillNag/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
$bmp.Save($iconPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "Wrote $iconPath"

# ---------- Alarm tones (16-bit mono PCM WAV) ----------
$rate = 22050

function Write-Wav([string]$path, [double[]]$samples) {
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter $ms
    $dataLen = $samples.Length * 2
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF')); $bw.Write([int](36 + $dataLen))
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('WAVE'))
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('fmt ')); $bw.Write([int]16)
    $bw.Write([int16]1); $bw.Write([int16]1); $bw.Write([int]$rate); $bw.Write([int]($rate * 2))
    $bw.Write([int16]2); $bw.Write([int16]16)
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('data')); $bw.Write([int]$dataLen)
    foreach ($s in $samples) {
        $v = [Math]::Max(-1.0, [Math]::Min(1.0, $s))
        $bw.Write([int16]([Math]::Round($v * 30000)))
    }
    $bw.Flush()
    [System.IO.File]::WriteAllBytes($path, $ms.ToArray())
    Write-Host "Wrote $path"
}

# notes: array of @(startSec, freq, durSec, decay, gain)
function Render([double]$length, $notes) {
    $n = [int]($length * $rate)
    $buf = New-Object double[] $n
    foreach ($note in $notes) {
        $start = [int]($note[0] * $rate); $freq = $note[1]; $dur = [int]($note[2] * $rate)
        $decay = $note[3]; $gain = $note[4]
        for ($i = 0; $i -lt $dur -and ($start + $i) -lt $n; $i++) {
            $t = $i / $rate
            $attack = [Math]::Min(1.0, $i / ($rate * 0.008))
            $release = [Math]::Min(1.0, ($dur - $i) / ($rate * 0.02))
            $env = $attack * $release * [Math]::Exp(-$decay * $t)
            $v = [Math]::Sin(2 * [Math]::PI * $freq * $t) + 0.35 * [Math]::Sin(4 * [Math]::PI * $freq * $t) + 0.12 * [Math]::Sin(6 * [Math]::PI * $freq * $t)
            $buf[$start + $i] += $gain * $env * $v / 1.47
        }
    }
    return , $buf
}

$out = Join-Path $root 'PillNag/Resources/Sounds'
New-Item -ItemType Directory -Force $out | Out-Null

Write-Wav (Join-Path $out 'chime.wav') (Render 4.0 @(
    @(0.0, 1318.5, 1.6, 2.2, 0.8), @(0.35, 987.8, 1.8, 2.0, 0.8),
    @(2.0, 1318.5, 1.6, 2.2, 0.8), @(2.35, 987.8, 1.6, 2.0, 0.8)))

Write-Wav (Join-Path $out 'pulse.wav') (Render 3.0 @(
    @(0.0, 880, 0.14, 1, 0.9), @(0.2, 880, 0.14, 1, 0.9), @(0.4, 880, 0.14, 1, 0.9),
    @(1.5, 880, 0.14, 1, 0.9), @(1.7, 880, 0.14, 1, 0.9), @(1.9, 880, 0.14, 1, 0.9)))

Write-Wav (Join-Path $out 'rise.wav') (Render 4.0 @(
    @(0.0, 523.25, 0.5, 3, 0.8), @(0.18, 659.25, 0.5, 3, 0.8), @(0.36, 783.99, 0.5, 3, 0.8), @(0.54, 1046.5, 1.0, 2.5, 0.8),
    @(2.0, 523.25, 0.5, 3, 0.8), @(2.18, 659.25, 0.5, 3, 0.8), @(2.36, 783.99, 0.5, 3, 0.8), @(2.54, 1046.5, 1.0, 2.5, 0.8)))

Write-Wav (Join-Path $out 'gentle.wav') (Render 4.0 @(
    @(0.0, 587.33, 1.8, 1.6, 0.6), @(0.6, 739.99, 1.8, 1.6, 0.5),
    @(2.0, 587.33, 1.8, 1.6, 0.6), @(2.6, 880.0, 1.4, 1.6, 0.5)))
