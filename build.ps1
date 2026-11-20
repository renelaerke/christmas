# Builds JuleHygge.exe with the C# compiler that ships with Windows (.NET Framework 4.x).
# The app icon is drawn here at build time, so the repo contains no image files.
# -Version x.y.z stamps the exe (the GitHub workflow passes the release tag). Without it the exe is 0.0.0,
# a development build that never updates itself.
param([string]$Version = '0.0.0')
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { Write-Error "Version must look like 1.2.3, got '$Version'"; exit 1 }
Add-Type -AssemblyName System.Drawing

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
$out = Join-Path $PSScriptRoot 'JuleHygge.exe'
$ico = Join-Path $PSScriptRoot 'JuleHygge.ico'

# Draws the snowflake icon (same design as the tray icon) at the given pixel size and returns a Bitmap.
function New-IconBitmap([int]$size) {
    $k = $size / 32.0
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $rect = New-Object System.Drawing.RectangleF (1 * $k), (1 * $k), (30 * $k), (30 * $k)
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(225, 45, 55)), ([System.Drawing.Color]::FromArgb(160, 15, 25)), 90.0
    $g.FillEllipse($bg, $rect)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), ([Math]::Max(1.2, 2.2 * $k))
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $c = 16 * $k
    for ($i = 0; $i -lt 3; $i++) {
        $a = $i * [Math]::PI / 3 + [Math]::PI / 2
        $dx = [Math]::Cos($a) * 11 * $k; $dy = [Math]::Sin($a) * 11 * $k
        $g.DrawLine($pen, [float]($c - $dx), [float]($c - $dy), [float]($c + $dx), [float]($c + $dy))
        if ($size -lt 24) { continue }   # branches are just noise at tiny sizes
        foreach ($sgn in -1, 1) {
            $ex = $c + $sgn * $dx * 0.65; $ey = $c + $sgn * $dy * 0.65
            $a1 = $a + $(if ($sgn -gt 0) { 0 } else { [Math]::PI })
            foreach ($side in -1, 1) {
                $ba = $a1 + $side * 2.4
                $g.DrawLine($pen, [float]$ex, [float]$ey, [float]($ex + [Math]::Cos($ba) * 4 * $k), [float]($ey + [Math]::Sin($ba) * 4 * $k))
            }
        }
    }
    $g.Dispose()
    return $bmp
}

# Encodes one icon entry: PNG for 256 px, classic 32-bit DIB (BGRA + AND mask) for smaller sizes,
# because many readers (including System.Drawing.Icon) only understand PNG in the 256 px entry.
function Get-IconEntryBytes([int]$size) {
    $bmp = New-IconBitmap $size
    $ms = New-Object System.IO.MemoryStream
    if ($size -ge 256) {
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    } else {
        $w = New-Object System.IO.BinaryWriter $ms
        $maskStride = [int]([Math]::Ceiling($size / 32.0) * 4)
        # BITMAPINFOHEADER; height is doubled to cover the XOR image plus the AND mask
        $w.Write([uint32]40); $w.Write([int32]$size); $w.Write([int32]($size * 2))
        $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]0)
        $w.Write([uint32]($size * $size * 4 + $maskStride * $size))
        $w.Write([int32]0); $w.Write([int32]0); $w.Write([uint32]0); $w.Write([uint32]0)
        for ($y = $size - 1; $y -ge 0; $y--) {          # rows are stored bottom-up
            for ($x = 0; $x -lt $size; $x++) {
                $c = $bmp.GetPixel($x, $y)
                $w.Write([byte]$c.B); $w.Write([byte]$c.G); $w.Write([byte]$c.R); $w.Write([byte]$c.A)
            }
        }
        $w.Write((New-Object byte[] ($maskStride * $size)))   # all-zero mask; alpha channel does the work
        $w.Flush()
    }
    $bmp.Dispose()
    return , $ms.ToArray()
}

# Writes a multi-size .ico file.
function Write-Ico([string]$path, [int[]]$sizes) {
    $pngs = @($sizes | ForEach-Object { , (Get-IconEntryBytes $_) })
    $fs = [System.IO.File]::Create($path)
    $w = New-Object System.IO.BinaryWriter $fs
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $s = $sizes[$i]; $dim = if ($s -ge 256) { 0 } else { $s }
        $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([uint16]1); $w.Write([uint16]32)
        $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
        $offset += $pngs[$i].Length
    }
    foreach ($p in $pngs) { $w.Write($p) }
    $w.Close()
}

Write-Ico $ico @(16, 24, 32, 48, 64, 256)

# Version attributes, generated so the version lives only in the release tag.
$obj = Join-Path $PSScriptRoot 'obj'
New-Item -ItemType Directory -Force $obj | Out-Null
$versionFile = Join-Path $obj 'Version.cs'
@"
using System.Reflection;
[assembly: AssemblyTitle("JuleHygge")]
[assembly: AssemblyProduct("JuleHygge")]
[assembly: AssemblyVersion("$Version.0")]
[assembly: AssemblyFileVersion("$Version.0")]
[assembly: AssemblyInformationalVersion("$Version")]
"@ | Set-Content -Path $versionFile -Encoding UTF8

& $csc /nologo /codepage:65001 /target:winexe /optimize+ /unsafe /platform:anycpu /out:$out `
    /win32icon:$ico `
    "/resource:$(Join-Path $PSScriptRoot 'assets\lyd\gaes-flok.wav'),gaes-flok.wav" `
    /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll `
    (Join-Path $PSScriptRoot 'src\*.cs') $versionFile
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed"; exit 1 }
Write-Host "Built: $out (version $Version)"
