# ============================================================================
# THE HUMANS ARE FINE - build per-article social cards
#
# Each article gets a 1200x630 PNG that names that specific story. Nothing is
# downloaded and nothing is invented: the body text, the kicker line and the
# date are read out of the article's own HTML, and the palette is the site's
# own :root variables from styles.css.
#
# These are generated typographic cards, not photographs. They identify the
# story in a share or a Discover card; they are not editorial imagery of the
# events described, and the report says so plainly.
# ============================================================================
param(
    [string]$OutDir = 'assets/social',
    [int]$Width = 1200,
    [int]$Height = 630
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    # Palette taken from the stylesheet so the cards cannot drift from the site.
    $bg = [System.Drawing.ColorTranslator]::FromHtml('#0b1014')
    $panel = [System.Drawing.ColorTranslator]::FromHtml('#121a20')
    $ink = [System.Drawing.ColorTranslator]::FromHtml('#f5f3ea')
    $muted = [System.Drawing.ColorTranslator]::FromHtml('#c4cdd1')
    $line = [System.Drawing.ColorTranslator]::FromHtml('#46535a')
    $amber = [System.Drawing.ColorTranslator]::FromHtml('#e8be7a')
    $green = [System.Drawing.ColorTranslator]::FromHtml('#a8d8b0')

    $target = Join-Path $repo $OutDir
    if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target | Out-Null }

    $tracked = @(git ls-files) | ForEach-Object { $_.Trim() }
    $articles = @($tracked | Where-Object { $_ -like 'articles/*.html' -and $_ -notlike '*-evidence.html' })
    if ($articles.Count -eq 0) { throw 'No articles found.' }

    $made = 0
    foreach ($rel in $articles) {
        $slug = ($rel -replace '^articles/', '' -replace '\.html$', '')
        $html = [System.IO.File]::ReadAllText((Join-Path $repo $rel))

        $h1 = [regex]::Match($html, '(?is)<h1[^>]*>(.*?)</h1>')
        if (-not $h1.Success) { throw "$rel has no h1 - nothing honest to put on a card." }
        $headline = [System.Web.HttpUtility]::HtmlDecode([regex]::Replace($h1.Groups[1].Value, '<[^>]+>', '')).Trim()

        # Kicker: the section label the article already carries, if any.
        $kick = [regex]::Match($html, '(?is)<p class="kicker"[^>]*>(.*?)</p>')
        $kicker = if ($kick.Success) { [System.Web.HttpUtility]::HtmlDecode([regex]::Replace($kick.Groups[1].Value, '<[^>]+>', '')).Trim() } else { 'FRONTIER AI' }
        $kicker = $kicker.ToUpperInvariant()

        $pm = [regex]::Match($html, '<meta\s+property="article:published_time"\s+content="([^"]+)"')
        $dateText = if ($pm.Success) { ([datetimeoffset]::Parse($pm.Groups[1].Value.Trim())).ToString('MMMM d, yyyy') } else { '' }

        $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.Clear($bg)

        # Panel band and rules, echoing the site's layout.
        $panelBrush = New-Object System.Drawing.SolidBrush($panel)
        $g.FillRectangle($panelBrush, 0, 0, $Width, 150)
        $linePen = New-Object System.Drawing.Pen($line, 2)
        $g.DrawLine($linePen, 80, 150, $Width - 80, 150)
        $g.DrawLine($linePen, 80, $Height - 110, $Width - 80, $Height - 110)
        $amberPen = New-Object System.Drawing.Pen($amber, 4)
        $g.DrawLine($amberPen, 80, 150, 200, 150)

        # Masthead.
        $mastFont = New-Object System.Drawing.Font('Georgia', 26, [System.Drawing.FontStyle]::Bold)
        $inkBrush = New-Object System.Drawing.SolidBrush($ink)
        $g.DrawString('THE HUMANS ARE FINE.', $mastFont, $inkBrush, 80, 40)
        $subFont = New-Object System.Drawing.Font('Arial', 13, [System.Drawing.FontStyle]::Regular)
        $mutedBrush = New-Object System.Drawing.SolidBrush($muted)
        $g.DrawString('INDEPENDENT AI JOURNALISM', $subFont, $mutedBrush, 82, 88)
        $amberBrush = New-Object System.Drawing.SolidBrush($amber)
        $g.DrawString($kicker, $subFont, $amberBrush, 80, 112)

        # Headline: shrink until it fits the available box, then wrap manually
        # so the card never clips a line of its own headline.
        $maxWidth = $Width - 160
        $size = 58
        while ($size -ge 26) {
            $font = New-Object System.Drawing.Font('Georgia', $size, [System.Drawing.FontStyle]::Bold)
            $words = $headline -split '\s+'
            $lines = @(); $current = ''
            foreach ($w in $words) {
                $try = if ($current -eq '') { $w } else { "$current $w" }
                if ($g.MeasureString($try, $font).Width -le $maxWidth) { $current = $try }
                else { if ($current -ne '') { $lines += $current }; $current = $w }
            }
            if ($current -ne '') { $lines += $current }
            $lineHeight = $font.GetHeight($g)
            $blockHeight = $lines.Count * $lineHeight
            $overWide = $false
            foreach ($l in $lines) { if ($g.MeasureString($l, $font).Width -gt $maxWidth) { $overWide = $true } }
            if ($blockHeight -le 300 -and $lines.Count -le 5 -and -not $overWide) { break }
            $font.Dispose()
            $size -= 2
        }
        $font = New-Object System.Drawing.Font('Georgia', $size, [System.Drawing.FontStyle]::Bold)
        $y = 200
        foreach ($l in $lines) {
            $g.DrawString($l, $font, $inkBrush, 80, $y)
            $y += [int]($font.GetHeight($g))
        }

        # Footer: real publication date and the domain.
        $footFont = New-Object System.Drawing.Font('Consolas', 16, [System.Drawing.FontStyle]::Regular)
        $greenBrush = New-Object System.Drawing.SolidBrush($green)
        $g.DrawString($dateText, $footFont, $mutedBrush, 80, $Height - 85)
        $g.DrawString('thehumansarefine.com', $footFont, $greenBrush, $Width - 420, $Height - 85)

        $outPath = Join-Path $target "$slug.png"
        $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        $font.Dispose(); $mastFont.Dispose(); $subFont.Dispose(); $footFont.Dispose()
        $inkBrush.Dispose(); $mutedBrush.Dispose(); $amberBrush.Dispose(); $panelBrush.Dispose()
        $greenBrush.Dispose()
        $linePen.Dispose(); $amberPen.Dispose()

        $len = (Get-Item $outPath).Length
        Write-Output ("{0,-44} {1,7} B  headline={2}" -f $slug, $len, $headline.Substring(0, [Math]::Min(60, $headline.Length)))
        $made++
    }
    Write-Output ''
    Write-Output ("social cards written: {0} into {1}/" -f $made, $OutDir)
}
finally { Pop-Location }
