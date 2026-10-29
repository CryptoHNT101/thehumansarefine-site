# ============================================================================
# THE HUMANS ARE FINE - add a real, visible breadcrumb trail to article pages
#
# Why: articles were reachable only by guessing a URL. The kicker at the top of
# each story already links to that story's topic archive, so the trail
# Home > <topic> > <story> is not invented here - it is read off the page's own
# kicker. The same derivation is used by thaf-apply-metadata.ps1 to emit the
# matching BreadcrumbList markup, so markup and visible trail cannot drift.
#
# Idempotent: the inserted block is fenced by markers and replaced on re-run.
# ============================================================================
param([switch]$WhatIf, [switch]$Force)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    # display name for each topic archive, taken from that page's own title
    $topicName = @{}
    foreach ($t in @(git ls-files 'topics/*.html')) {
        $html = [IO.File]::ReadAllText((Resolve-Path $t))
        $title = ([regex]::Match($html, '(?is)<title>(.*?)</title>')).Groups[1].Value
        # titles are authored in HTML, so the separator arrives as an entity
        $name = ($title -split '&mdash;')[0]
        $name = ($name -split [char]0x2014)[0]
        $name = ($name -split '&amp;mdash;')[0]
        $name = $name.Replace('&amp;', '&').Trim()
        if (-not $name) { throw "cannot derive a display name from $t" }
        $topicName[$t] = $name
    }
    Write-Output ('topics: ' + (($topicName.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' | '))

    $changed = 0; $skipped = 0; $noKicker = New-Object System.Collections.Generic.List[string]

    foreach ($rel in @(git ls-files 'articles/*.html' | Sort-Object)) {
        $full = Join-Path $repo $rel
        $html = [IO.File]::ReadAllText($full)
        $original = $html

        $kick = [regex]::Match($html, '(?is)<p class="kicker[^"]*"><a href="\.\./(topics/[a-z0-9\-]+\.html)">(.*?)</a>')
        $topicRel = if ($kick.Success) { $kick.Groups[1].Value } else { $null }

        # Some Evidence Files carry a kicker with no link. Their real position in
        # the tree is stated on the page itself: the "Article" row of the meta
        # list names the companion story. Inherit that story's topic rather than
        # guessing one.
        if (-not $topicRel) {
            $comp = [regex]::Match($html, '(?is)<li><b>Article</b>\s*<a href="([a-z0-9\-]+\.html)">')
            if ($comp.Success) {
                $compPath = Split-Path $rel -Parent
                $compRel = ($compPath -replace '\\', '/') + '/' + $comp.Groups[1].Value
                if (Test-Path $compRel) {
                    $compHtml = [IO.File]::ReadAllText((Resolve-Path $compRel))
                    $ck = [regex]::Match($compHtml, '(?is)<p class="kicker[^"]*"><a href="\.\./(topics/[a-z0-9\-]+\.html)">')
                    if ($ck.Success) {
                        $topicRel = $ck.Groups[1].Value
                        Write-Output ("  $rel inherits topic from companion $($comp.Groups[1].Value)")
                    }
                }
            }
        }
        if (-not $topicRel) { $noKicker.Add($rel); continue }
        $topicNameText = $topicName[$topicRel]
        if (-not $topicNameText) { throw "$rel links to $topicRel which is not a tracked topic page." }

        $h1 = ([regex]::Match($html, '(?is)<h1>(.*?)</h1>')).Groups[1].Value
        if (-not $h1) { $h1 = ([regex]::Match($html, '(?is)<title>(.*?)</title>')).Groups[1].Value }
        $h1 = $h1.Trim()
        # The trail's last crumb is a short label, not a 142-character headline.
        # The page's own <title> is the newspaper's short name for the story, so
        # it is preferred when it is short enough to read in a breadcrumb.
        $short = ([regex]::Match($html, '(?is)<title>(.*?)</title>')).Groups[1].Value.Trim()
        $crumbLabel = if ($short -and $short.Length -le 64) { $short } else { $h1 }
        if ($crumbLabel.Length -gt 64) {
            $cut = $crumbLabel.LastIndexOf(' ', 60)
            if ($cut -lt 24) { $cut = 60 }
            $crumbLabel = $crumbLabel.Substring(0, $cut).TrimEnd(' ,;:') + [char]0x2026
        }
        $crumbLabel = $crumbLabel.Replace('&amp;', '&').Replace('&quot;', '"')
        $crumbLabel = [System.Security.SecurityElement]::Escape($crumbLabel)

        $nav = @()
        $nav += '<!-- thaf-crumbs:begin -->'
        $nav += '<nav class="crumbs wrap" aria-label="Breadcrumb"><a href="../index.html">Home</a> <span aria-hidden="true">&rsaquo;</span> <a href="../' + $topicRel + '">' + $topicNameText + '</a> <span aria-hidden="true">&rsaquo;</span> <span aria-current="page">' + $crumbLabel + '</span></nav>'
        $nav += '<!-- thaf-crumbs:end -->'
        $block = ($nav -join "`r`n")

        # A trail that already exists is left exactly as it is unless -Force is
        # passed: the labels were chosen from the page's short title at the time
        # it was added, and re-deriving them later would silently rewrite them.
        $hadBlock = $html.Contains('<!-- thaf-crumbs:begin -->')
        if ($hadBlock -and -not $Force) { $skipped++; continue }
        $html = [regex]::Replace($html, '(?s)<!-- thaf-crumbs:begin -->.*?<!-- thaf-crumbs:end -->', '')

        # place it immediately before the kicker paragraph. The offset must be
        # re-measured on the STRIPPED string: any previous crumb block sat above
        # the kicker, so the old index would land mid-tag on a second run.
        # anchor: the kicker if this page has one, else the h1, else the article
        # element. Some Evidence Files open with die-straight copy and no kicker.
        $anchorAt = -1
        foreach ($pat in @(
            '(?is)<p class="kicker[^"]*"><a href="\.\./topics/[a-z0-9\-]+\.html">',
            '(?is)<p class="kicker[^"]*">',
            '(?is)<h1[^>]*>',
            '(?is)<article[^>]*>'
        )) {
            $mm = [regex]::Match($html, $pat)
            if ($mm.Success) { $anchorAt = $mm.Index; break }
        }
        if ($anchorAt -lt 0) { $noKicker.Add($rel); continue }
        $anchor = $anchorAt
        $html = $html.Substring(0, $anchor) + $block + "`r`n" + $html.Substring($anchor)

        if ($html -eq $original) { $skipped++; continue }
        if (-not $WhatIf) {
            [IO.File]::WriteAllText($full, $html, (New-Object System.Text.UTF8Encoding($false)))
        }
        $changed++
        Write-Output ("  $rel  ->  Home > $topicNameText > $crumbLabel")
    }

    foreach ($m in $noKicker) { Write-Output ("  NO KICKER (skipped): " + $m) }
    Write-Output ("breadcrumbs changed={0} unchanged={1} whatIf={2}" -f $changed, $skipped, [bool]$WhatIf)
}
finally { Pop-Location }
