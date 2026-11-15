# ASCII only: Windows PowerShell 5.1 reads a BOM-less script in the ANSI code page.
#
# Builds the installer dist\Win11Privacy-Setup.exe from an already built
# Win11Privacy.exe (build.cmd or the CI step "build Win11Privacy.exe"):
#   1. reads the version from AppInfo.cs,
#   2. draws the wizard pictures from app.png into installer\obj,
#   3. runs the Inno Setup compiler (ISCC.exe, Inno Setup 6.6 or newer) on
#      installer\Win11Privacy.iss.
#
#   powershell -ExecutionPolicy Bypass -File installer\build.ps1 [-Iscc <path to ISCC.exe>]
#
# The installer offers both a regular installation (Program Files, Start menu,
# removal in Settings > Apps) and a portable copy (unpacked into a folder with
# portable.txt, nothing registered) - the person picks one in the wizard.
param(
    [string]$Iscc = '',
    [string]$SourceDir = '',
    [string]$OutDir = '',
    [switch]$ImagesOnly          # only draw the wizard pictures into installer\obj (to look at them)
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
if (-not $SourceDir) { $SourceDir = $root }
if (-not $OutDir) { $OutDir = Join-Path $root 'dist' }
$SourceDir = (Resolve-Path $SourceDir).Path

# --- version ------------------------------------------------------------------
$info = Get-Content -LiteralPath (Join-Path $root 'AppInfo.cs') -Raw -Encoding UTF8
$m = [regex]::Match($info, 'Version\s*=\s*"([0-9.]+)"')
if (-not $m.Success) { throw 'AppInfo.cs: version string not found' }
$version = $m.Groups[1].Value

foreach ($need in @('Win11Privacy.exe', 'LICENSE', 'app.ico')) {
    if ($ImagesOnly) { break }
    if (-not (Test-Path -LiteralPath (Join-Path $SourceDir $need))) {
        throw "$need not found in $SourceDir - build Win11Privacy.exe first (build.cmd)"
    }
}

# --- compiler -----------------------------------------------------------------
if (-not $Iscc -and -not $ImagesOnly) {
    $cands = @($env:ISCC,
               (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
               (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
               (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'))
    foreach ($c in $cands) { if ($c -and (Test-Path -LiteralPath $c)) { $Iscc = $c; break } }
}
if (-not $ImagesOnly -and (-not $Iscc -or -not (Test-Path -LiteralPath $Iscc))) {
    throw 'ISCC.exe (Inno Setup 6.6+) not found: install Inno Setup or pass -Iscc'
}

# --- wizard pictures ----------------------------------------------------------
# Welcome / Finished pages (aspect 164:314): dark panel with a soft accent
# glow, the app icon and the name. The other pages have no small picture in
# the top-right corner (hidden by the script).
Add-Type -AssemblyName System.Drawing
$obj = Join-Path $here 'obj'
New-Item -ItemType Directory -Force $obj | Out-Null
$icon = [System.Drawing.Image]::FromFile((Join-Path $root 'app.png'))

function New-Canvas([int]$w, [int]$h) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    return @($bmp, $g)
}

foreach ($scale in @(100, 150, 200)) {
    $k = $scale / 100.0
    # large
    $w = [int](164 * $k); $h = [int](314 * $k)
    $c = New-Canvas $w $h; $bmp = $c[0]; $g = $c[1]
    # No version and no language-specific text: the same picture suits every
    # release and both wizard languages.
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect,
            [System.Drawing.Color]::FromArgb(255, 24, 34, 56), [System.Drawing.Color]::FromArgb(255, 9, 11, 17), 90.0)
    $g.FillRectangle($bg, $rect)
    $iw = [int]($w * 0.50)
    $cx = $w / 2.0; $cy = $h * 0.40
    $ix = [int]($cx - $iw / 2); $iy = [int]($cy - $iw / 2)
    # soft accent glow behind the icon
    $gr = $w * 0.95
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddEllipse([single]($cx - $gr), [single]($cy - $gr), [single](2 * $gr), [single](2 * $gr))
    $pg = New-Object System.Drawing.Drawing2D.PathGradientBrush($path)
    $pg.CenterColor = [System.Drawing.Color]::FromArgb(110, 47, 110, 235)
    $pg.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 47, 110, 235))
    $g.FillPath($pg, $path)
    $pg.Dispose(); $path.Dispose()
    # thin rings, like a shield's pulse, fading outwards
    $ringR = @(0.40, 0.54, 0.68, 0.82)
    for ($i = 0; $i -lt $ringR.Count; $i++) {
        $r = $w * $ringR[$i]
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb([int](46 - 10 * $i), 160, 190, 255), [single](1.0 * $k))
        $g.DrawEllipse($pen, [single]($cx - $r), [single]($cy - $r), [single](2 * $r), [single](2 * $r))
        $pen.Dispose()
    }
    # shadow under the icon, then the icon
    for ($i = 1; $i -le 6; $i++) {
        $sh = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(14, 0, 0, 0))
        $d = [single](($i * 1.6) * $k)
        $g.FillEllipse($sh, [single]($ix + $iw * 0.10 - $d), [single]($iy + $iw * 0.80 - $d / 2), [single]($iw * 0.80 + 2 * $d), [single]($iw * 0.28 + $d))
        $sh.Dispose()
    }
    $g.DrawImage($icon, $ix, $iy, $iw, $iw)
    # name
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = 'Center'
    $f1 = New-Object System.Drawing.Font('Segoe UI Semibold', [single](14.5 * $k), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 238, 242, 250))
    $ty = [single]($iy + $iw + [int](22 * $k))
    $r1 = New-Object System.Drawing.RectangleF([single]0, $ty, [single]$w, [single](26 * $k))
    $g.DrawString('Win11Privacy', $f1, $white, $r1, $fmt)
    # short accent line under the name
    $lw = [single](22 * $k)
    $acc = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 59, 130, 246))
    $g.FillRectangle($acc, [single]($cx - $lw / 2), [single]($ty + 27 * $k), $lw, [single](2 * $k))
    $acc.Dispose(); $white.Dispose(); $f1.Dispose()
    $g.Dispose()
    $bmp.Save((Join-Path $obj "wizard-$scale.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}
$icon.Dispose()
if ($ImagesOnly) { Write-Host "wizard pictures: $obj"; exit 0 }

# --- compile ------------------------------------------------------------------
New-Item -ItemType Directory -Force $OutDir | Out-Null
$iss = Join-Path $here 'Win11Privacy.iss'
& $Iscc '/Qp' "/DAppVersion=$version" "/DSourceDir=$SourceDir" "/DImgDir=$obj" "/DOutDir=$OutDir" $iss
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }
$setup = Join-Path $OutDir 'Win11Privacy-Setup.exe'
if (-not (Test-Path -LiteralPath $setup)) { throw "ISCC finished but $setup is missing" }
$hash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLower()
Write-Host ("installer: {0} ({1:N0} bytes), version {2}" -f $setup, (Get-Item -LiteralPath $setup).Length, $version)
Write-Host ("sha256: {0}" -f $hash)
exit 0
