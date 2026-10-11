# Generates the adaptive / themed launcher-icon layers for RouteNote.
#
# The design source (assets/app_icon.png) is a full-bleed, fully opaque white
# canvas with a dark-blue map-pin glyph. This script extracts the glyph
# (everything that isn't near-white) and renders:
#
#   -Phase assets:  released assets consumed at build time by
#                   flutter_launcher_icons (pubspec.yaml):
#                       assets/app_icon_foreground.png   glyph, safe-zone centered
#                       assets/app_icon_monochrome.png   white silhouette for
#                                                        Android 13+ Material You
#   -Phase res:     the dark alt-icon used by the dynamic dark/light switch
#                   (lib/src/services/dynamic_icon_service.dart):
#                       res/mipmap-anydpi-v26/ic_launcher_dark.xml
#                       res/drawable|mipmap-*/ic_launcher_dark_foreground.png
#                       res/mipmap-*/ic_launcher_dark.png (legacy <API 26)
#                   mirrored onto the exact paths/sizes the launcher-icon
#                   generator already produced for ic_launcher_foreground.
#
# Usage (from the repo root, after `dart run flutter_launcher_icons`):
#   powershell -ExecutionPolicy Bypass -File tool\gen_dark_icon.ps1 -Phase assets
#   dart run flutter_launcher_icons
#   powershell -ExecutionPolicy Bypass -File tool\gen_dark_icon.ps1 -Phase res
param(
    [ValidateSet("assets", "res")] [string]$Phase = "assets",
    [string]$ProjectDir = ([System.IO.Path]::GetFullPath((Resolve-Path ".").Path))
)

Add-Type -AssemblyName System.Drawing

$whiteThresh = 247
$blueMin     = 25    # B-R below this = white canvas, grey drop-shadow, or noise
$fgFit       = 0.58   # adaptive foreground: glyph fills 58% of the canvas
$legacyFit   = 0.60   # legacy (<API 26) dark icon: glyph fills 60%
$darkBg      = "#0D1B2A"  # dark navy backdrop for the dark variant

function New-AssetsFile([System.Drawing.Bitmap]$src, [string]$path, [int]$size, [double]$fit, [string]$bgHex, [bool]$white) {
    $canvas = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gfx = [System.Drawing.Graphics]::FromImage($canvas)
    $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    if ($bgHex -ne '') { $gfx.Clear([System.Drawing.ColorTranslator]::FromHtml($bgHex)) }
    $bw = $Script:maxX - $Script:minX + 1
    $bh = $Script:maxY - $Script:minY + 1
    $scale = $fit * $size / [Math]::Max($bw, $bh)
    $dw = [Math]::Max(1, [int]($bw * $scale))
    $dh = [Math]::Max(1, [int]($bh * $scale))
    $dx = [int](($size - $dw) / 2)
    $dy = [int](($size - $dh) / 2)
    $dstRect = New-Object System.Drawing.Rectangle($dx, $dy, $dw, $dh)
    $gfx.DrawImage($src, $dstRect)
    $gfx.Dispose()
    $full = Join-Path $ProjectDir $path
    New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null
    $canvas.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Dispose()
    Write-Output ("wrote {0} ({1}x{1}, glyph at {2},{3} size {4}x{5})" -f $path.Split('\')[-1], $size, $dx, $dy, $dw, $dh)
}

# --- extract the glyph (opaque / non-near-white pixels) from the source ---------
$srcPath = Join-Path $ProjectDir "assets\app_icon.png"
$src = [System.Drawing.Bitmap]::FromFile($srcPath)
$W = $src.Width
if ($src.Height -ne $W) { throw "source icon must be square (found $W x $($src.Height))" }

$rect = New-Object System.Drawing.Rectangle(0, 0, $W, $W)
$data = $src.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$srcStride = $data.Stride
$bytes = New-Object byte[] ($srcStride * $W)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
$src.UnlockBits($data)
$src.Dispose()

$stride = 4 * $W
$glyph = New-Object byte[] ($stride * $W)
$Script:minX = $W; $Script:minY = $W; $Script:maxX = -1; $Script:maxY = -1
for ($y = 0; $y -lt $W; $y++) {
    for ($x = 0; $x -lt $W; $x++) {
        $i = $y * $srcStride + $x * 4
        $b = $bytes[$i]; $g = $bytes[$i + 1]; $r = $bytes[$i + 2]
        # The pin glyph is saturated blue (B clearly exceeds R). White canvas,
        # the soft grey drop-shadow and faint edge noise all fail this rule, so
        # the extracted silhouette is exactly the pin.
        if (($b - $r) -le $blueMin) { continue }
        if ($x -lt $Script:minX) { $Script:minX = $x }
        if ($x -gt $Script:maxX) { $Script:maxX = $x }
        if ($y -lt $Script:minY) { $Script:minY = $y }
        if ($y -gt $Script:maxY) { $Script:maxY = $y }
        $j = $y * $stride + $x * 4
        $glyph[$j] = $b; $glyph[$j + 1] = $g; $glyph[$j + 2] = $r; $glyph[$j + 3] = 255
    }
}
Write-Output ("glyph bbox: {0},{1} -> {2},{3}" -f $Script:minX, $Script:minY, $Script:maxX, $Script:maxY)

# Fill interior holes (the pin head's specular glare is near-white, so the
# chroma rule punches small holes). Exterior transparent pixels are reached by
# a 4-connected flood fill from the canvas border; anything left transparent
# is an enclosed hole and becomes pin surface again.
$exterior = New-Object byte[] ($W * $W)
$stack = New-Object System.Collections.Generic.Stack[int]
for ($x = 0; $x -lt $W; $x++) {
    if ($glyph[$x * 4 + 3] -eq 0) { $exterior[$x] = 2; $stack.Push($x) }                       # top row
    $bi = ($W - 1) * $W + $x
    if ($glyph[($W - 1) * $stride + $x * 4 + 3] -eq 0) { $exterior[$bi] = 2; $stack.Push($bi) } # bottom row
}
for ($y = 1; $y -lt ($W - 1); $y++) {
    $li = $y * $W
    if ($glyph[$y * $stride + 3] -eq 0) { $exterior[$li] = 2; $stack.Push($li) }                # left col
    $ri = $y * $W + $W - 1
    if ($glyph[$y * $stride + ($W - 1) * 4 + 3] -eq 0) { $exterior[$ri] = 2; $stack.Push($ri) }  # right col
}
while ($stack.Count -gt 0) {
    $idx = $stack.Pop()
    $x = $idx % $W; $y = [int]($idx / $W)
    if ($x -gt 0)       { $n = $idx - 1;         if ($exterior[$n] -eq 0 -and $glyph[$n * 4 + 3] -eq 0) { $exterior[$n] = 2; $stack.Push($n) } }
    if ($x -lt ($W - 1)) { $n = $idx + 1;       if ($exterior[$n] -eq 0 -and $glyph[$n * 4 + 3] -eq 0) { $exterior[$n] = 2; $stack.Push($n) } }
    if ($y -gt 0)       { $n = $idx - $W;       if ($exterior[$n] -eq 0 -and $glyph[$n * 4 + 3] -eq 0) { $exterior[$n] = 2; $stack.Push($n) } }
    if ($y -lt ($W - 1)) { $n = $idx + $W;      if ($exterior[$n] -eq 0 -and $glyph[$n * 4 + 3] -eq 0) { $exterior[$n] = 2; $stack.Push($n) } }
}
$holes = 0
for ($i = 0; $i -lt ($W * $W); $i++) {
    if ($exterior[$i] -eq 0 -and $glyph[$i * 4 + 3] -eq 0) {
        $glyph[$i * 4] = 96; $glyph[$i * 4 + 1] = 120; $glyph[$i * 4 + 2] = 220; $glyph[$i * 4 + 3] = 255
        $holes++
    }
}
Write-Output ("filled {0} interior hole pixels" -f $holes)

function New-BmpFromBgra([byte[]]$bgra) {
    $bmp = New-Object System.Drawing.Bitmap($W, $W, $stride, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb, [IntPtr]::Zero)
    $r = New-Object System.Drawing.Rectangle(0, 0, $W, $W)
    $d = $bmp.LockBits($r, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    [System.Runtime.InteropServices.Marshal]::Copy($bgra, 0, $d.Scan0, $bgra.Length)
    $bmp.UnlockBits($d)
    return $bmp
}

$glyphBmp = New-BmpFromBgra $glyph
# white silhouette: keep the alpha mask, force RGB to white
$whiteGlyph = $glyph.Clone()  # byte[] clone then mutate
for ($i = 0; $i -lt $whiteGlyph.Length; $i += 4) {
    if ($whiteGlyph[$i + 3] -eq 0) { continue }
    $whiteGlyph[$i] = 255; $whiteGlyph[$i + 1] = 255; $whiteGlyph[$i + 2] = 255
}
$whiteGlyphBmp = New-BmpFromBgra $whiteGlyph

if ($Phase -eq "assets") {
    New-AssetsFile $glyphBmp       "assets\app_icon_foreground.png" 1024 $fgFit ""     $false
    New-AssetsFile $whiteGlyphBmp  "assets\app_icon_monochrome.png" 1024 $fgFit ""     $true
    Write-Output "assets phase done"
    exit 0
}

# --- res phase: dark alt icon, mirrored onto the generator's outputs ------------
if ($Phase -eq "res") {
    $resRoot = Join-Path $ProjectDir "android\app\src\main\res"
    # 1) require at least one density drawable emitted by flutter_launcher_icons
    $anyForeground = Get-ChildItem $resRoot -Recurse -Filter "ic_launcher_foreground.png" | Select-Object -First 1
    $anyXml = Join-Path $resRoot "mipmap-anydpi-v26"
    if ($null -eq $anyForeground) {
        Write-Output "res phase skipped: run 'dart run flutter_launcher_icons' first"
        exit 0
    }

    # dark foreground (white pin) for each size the generator emitted
    Get-ChildItem $resRoot -Recurse -Filter "ic_launcher_foreground.png" | ForEach-Object {
        $dir = $_.DirectoryName
        $size = ([System.Drawing.Bitmap]::FromFile($_.FullName)).Width
        $relative = $dir.Substring($ProjectDir.Length + 1) + "\ic_launcher_dark_foreground.png"
        New-AssetsFile $whiteGlyphBmp $relative $size $fgFit "" $true
    }

    # legacy dark icon (navy backdrop + white pin) in every mipmap density dir
    Get-ChildItem (Join-Path $resRoot "mipmap-*") -Directory | Where-Object { $_.Name -match "-(?:xxxhdpi|xxhdpi|xhdpi|hdpi|mdpi)$" } | ForEach-Object {
        $size = 48
        if ($_.Name -match "xxxhdpi$") { $size = 192 }
        elseif ($_.Name -match "xxhdpi$") { $size = 144 }
        elseif ($_.Name -match "xhdpi$") { $size = 96 }
        elseif ($_.Name -match "hdpi$") { $size = 72 }
        $relativeDark = $_.FullName.Substring($ProjectDir.Length + 1) + "\ic_launcher_dark.png"
        New-AssetsFile $whiteGlyphBmp $relativeDark $size $legacyFit $darkBg $true
    }

    # 2) adaptive XMLs referencing @color + @drawable resources
    $xml = '<?xml version="1.0" encoding="utf-8"?>' + "`n" +
'<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">' + "`n" +
'  <background android:drawable="@color/ic_launcher_dark_background"/>' + "`n" +
'  <foreground>' + "`n" +
'    <inset android:drawable="@drawable/ic_launcher_dark_foreground" android:inset="0%" />' + "`n" +
'  </foreground>' + "`n" +
'  <monochrome>' + "`n" +
'    <inset android:drawable="@drawable/ic_launcher_monochrome" android:inset="0%" />' + "`n" +
'  </monochrome>' + "`n" +
'</adaptive-icon>'
    New-Item -ItemType Directory -Force -Path $anyXml | Out-Null
    Set-Content -Path (Join-Path $anyXml "ic_launcher_dark.xml") -Value $xml -Encoding UTF8
    Write-Output "wrote mipmap-anydpi-v26/ic_launcher_dark.xml"
    Write-Output "res phase done (remember to add ic_launcher_dark_background to res/values/colors.xml)"
    exit 0
}