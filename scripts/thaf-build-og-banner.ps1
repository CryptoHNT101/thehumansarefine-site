# ============================================================================
# THE HUMANS ARE FINE - build the 1200x630 social-sharing card.
#
# Why this exists: every page shared one 1080x1080 square logo, which is the
# wrong aspect ratio for twitter:card=summary_large_image and gets cropped in
# every feed preview. This renders the masthead wordmark onto a 1200x630 canvas
# in the site's own colours (flat black ground, white bold geometric sans,
# centred, wide negative space on either side) - the same mark, in the shape
# social platforms actually display.
#
# No AI image generation and no invented artwork: the only content is the
# masthead string the site already displays on every page.
# ============================================================================
param(
    [string]$Out = 'assets/og-banner.png',
    [int]$Width = 1200,
    [int]$Height = 630
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    Add-Type -AssemblyName System.Drawing

    $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

        # flat black ground, exactly as the square mark
        $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0))

        # pick a real installed bold sans rather than hoping one exists
        $candidates = @('Segoe UI', 'Arial', 'Helvetica', 'Tahoma')
        $family = $null
        foreach ($name in $candidates) {
            $f = $null
            try { $f = New-Object System.Drawing.FontFamily($name) } catch { }
            if ($f -and $f.IsStyleAvailable([System.Drawing.FontStyle]::Bold)) { $family = $f; break }
        }
        if (-not $family) { throw 'No bold sans-serif family available to render the masthead.' }
        Write-Output ("font family: " + $family.Name)

        # fit the wordmark so it spans about the middle half of the width
        $targetWidth = $Width * 0.54
        $size = 40.0
        while ($size -lt 400) {
            $probe = New-Object System.Drawing.Font($family, $size, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
            $m = $g.MeasureString('THE HUMANS', $probe)
            $probe.Dispose()
            if ($m.Width -ge $targetWidth) { break }
            $size += 2
        }
        $size -= 2
        $font = New-Object System.Drawing.Font($family, $size, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = [System.Drawing.StringAlignment]::Center
        $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center

        # tight leading, matching the square mark: two stacked lines
        $line = $g.MeasureString('THE HUMANS', $font)
        $lead = [single]($line.Height * 0.86)
        $blockH = [single]($lead * 2)
        $cx = [single]($Width / 2)
        $y0 = [single](($Height - $blockH) / 2)
        $p1 = New-Object System.Drawing.PointF([single]$cx, [single]$y0)
        $y2 = [single]($y0 + $lead)
        $p2 = New-Object System.Drawing.PointF([single]$cx, $y2)
        $y3 = [single]($y0 + $blockH + ($size * 0.42))
        $p3 = New-Object System.Drawing.PointF([single]$cx, $y3)
        $g.DrawString('THE HUMANS', $font, $white, $p1, $fmt)
        $g.DrawString('ARE FINE.',  $font, $white, $p2, $fmt)
        $subFont = New-Object System.Drawing.Font($family, [single]($size * 0.19), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
        $grey = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 170, 170, 170))
        $g.DrawString('Independent AI journalism. Without human bias.', $subFont, $grey, $p3, $fmt)
        $subFont.Dispose(); $grey.Dispose()

        $fmt.Dispose(); $white.Dispose(); $font.Dispose()
    }
    finally { $g.Dispose() }

    $outPath = Join-Path $repo $Out
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    # prove the bytes on disk really are a 1200x630 PNG
    $bytes = [IO.File]::ReadAllBytes($outPath)
    if (-not ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47)) { throw 'output is not a PNG' }
    $w = [int]$bytes[16] * 16777216 + [int]$bytes[17] * 65536 + [int]$bytes[18] * 256 + [int]$bytes[19]
    $h = [int]$bytes[20] * 16777216 + [int]$bytes[21] * 65536 + [int]$bytes[22] * 256 + [int]$bytes[23]
    Write-Output ("wrote {0}: {1}x{2}, {3} bytes" -f $Out, $w, $h, $bytes.Length)
    if ($w -ne $Width -or $h -ne $Height) { throw "expected ${Width}x${Height}, got ${w}x${h}" }
}
finally { Pop-Location }
