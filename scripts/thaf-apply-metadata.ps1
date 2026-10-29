# ============================================================================
# THE HUMANS ARE FINE - search and social metadata injector
#
# Adds, to every tracked page, the metadata the Release 2 rebuild dropped:
#   og:image / og:site_name / article:published_time / article:modified_time
#   twitter:card / twitter:title / twitter:description / twitter:image
#   JSON-LD structured data (NewsArticle, CollectionPage, WebSite, WebPage)
#
# Honesty rules baked in:
#   * every date comes from page-dates.json, which comes from git history;
#     this script refuses to run if that file is absent or a page is missing.
#   * no author is invented as a person. The author is the newsroom
#     organisation, which is what the site's own disclosure page states.
#   * no aggregateRating, no review, no invented keywords, no fake breadcrumbs.
#   * the tag block is idempotent: it is fenced by markers and replaced on
#     re-run, so the script can be executed repeatedly without duplication.
#
# Audience build (Day 9) added, all derived rather than invented:
#   * og:image is now the 1200x630 social card, not the 1080x1080 square, so a
#     summary_large_image preview is no longer cropped. Dimensions are measured
#     from the PNG header, not typed in.
#   * every JSON-LD node carries an `image`, which Article rich results require.
#   * BreadcrumbList is emitted only for pages that actually display the trail,
#     and its labels are read off that visible trail; a page with no trail gets
#     no breadcrumb markup.
#   * articleSection is the real topic archive the story sits under, read from
#     the trail, instead of a generic "Articles".
# ============================================================================
param(
    [string]$DatesFile = 'scripts/page-dates.json',
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    if (-not (Test-Path $DatesFile)) {
        throw "Missing $DatesFile. Run scripts/thaf-page-dates.ps1 first - dates must come from git history, not from this script."
    }
    $dates = @{}
    foreach ($r in (Get-Content $DatesFile -Raw -Encoding UTF8 | ConvertFrom-Json)) {
        $dates[$r.path] = $r
    }

    $origin      = 'https://www.thehumansarefine.com'
    $siteName    = 'THE HUMANS ARE FINE'
    $publisherId = "$origin/#organization"

    # --- real image dimensions, measured from the file itself ---------------
    $imgPath = Join-Path $repo 'assets/thaf-flagship-profile.png'
    if (-not (Test-Path $imgPath)) { throw "Missing $imgPath - og:image would have to be invented." }
    function Png-Size([string]$path) {
        $b = [System.IO.File]::ReadAllBytes($path)
        if (-not ($b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47)) {
            throw "$path is not a PNG."
        }
        return [pscustomobject]@{
            W = [int]$b[16] * 16777216 + [int]$b[17] * 65536 + [int]$b[18] * 256 + [int]$b[19]
            H = [int]$b[20] * 16777216 + [int]$b[21] * 65536 + [int]$b[22] * 256 + [int]$b[23]
            N = $b.Length
        }
    }

    # the square mark stays the publisher logo; the wide card is what shares
    $logo = Png-Size $imgPath
    $logoUrl = "$origin/assets/thaf-flagship-profile.png"

    $ogPath = Join-Path $repo 'assets/og-banner.png'
    if (-not (Test-Path $ogPath)) {
        throw "Missing assets/og-banner.png. Run scripts/thaf-build-og-banner.ps1 first - a share image must not be invented here."
    }
    $og = Png-Size $ogPath
    if ($og.W -le $og.H) { throw "assets/og-banner.png is $($og.W)x$($og.H) - a share card must be wider than it is tall." }
    $imgUrl = "$origin/assets/og-banner.png"
    $imgW = $og.W
    $imgH = $og.H
    Write-Output ("og:image = {0} ({1}x{2}, {3} bytes)" -f $imgUrl, $imgW, $imgH, $og.N)
    Write-Output ("publisher logo = {0} ({1}x{2}, {3} bytes)" -f $logoUrl, $logo.W, $logo.H, $logo.N)

    function Decode-Basic([string]$s) {
        if ($null -eq $s) { return '' }
        $s = $s -replace '&mdash;', [char]0x2014
        $s = $s -replace '&ndash;', [char]0x2013
        $s = $s -replace '&amp;', '&'
        $s = $s -replace '&quot;', '"'
        $s = $s -replace '&apos;', "'"
        $s = $s -replace '&#39;', "'"
        $s = $s -replace '&rsquo;', [char]0x2019
        $s = $s -replace '&lsquo;', [char]0x2018
        $s = $s -replace '&nbsp;', ' '
        return $s.Trim()
    }
    function Esc([string]$s) { return [System.Security.SecurityElement]::Escape($s) }

    function Page-Url([string]$rel) {
        if ($rel -eq 'index.html') { return "$origin/" }
        if ($rel -match '^(.*/)index\.html$') { return "$origin/$($Matches[1])" }
        return "$origin/$rel"
    }
    function Page-Type([string]$rel) {
        if ($rel -match '^articles/.*-evidence\.html$') { return 'evidence' }
        if ($rel -match '^articles/.+\.html$')           { return 'article' }
        if ($rel -eq 'index.html')                        { return 'home' }
        if ($rel -match '^(news|topics|disclosure-watch)/') { return 'collection' }
        return 'page'
    }
    function Page-Section([string]$rel) {
        if ($rel -match '^topics/') { return 'Topics' }
        if ($rel -match '^articles/') { return 'Articles' }
        return 'News'
    }

    # The trail a reader can actually see. Returns $null when the page shows no
    # trail, and the caller then emits no BreadcrumbList at all.
    function Read-Trail([string]$html) {
        $nav = [regex]::Match($html, '(?is)<nav[^>]*class="crumbs[^"]*"[^>]*>(.*?)</nav>')
        if (-not $nav.Success) { return $null }
        $inner = $nav.Groups[1].Value
        # The anchor may carry data-thaf-event or any other attribute before
        # href; matching on the exact opening tag silently found no trail once
        # audience events were added to those links.
        $topic = [regex]::Match($inner, '(?is)<a [^>]*href="\.\./(topics/[a-z0-9\-]+\.html)"[^>]*>(.*?)</a>')
        $here  = [regex]::Match($inner, '(?is)<span aria-current="page">(.*?)</span>')
        if (-not $topic.Success -or -not $here.Success) { return $null }
        return [pscustomobject]@{
            TopicRel  = $topic.Groups[1].Value
            TopicName = (Decode-Basic $topic.Groups[2].Value)
            HereLabel = (Decode-Basic $here.Groups[1].Value)
        }
    }

    $files = @($dates.Keys) | Sort-Object
    $changed = 0; $skipped = 0

    foreach ($rel in $files) {
        $d       = $dates[$rel]
        $full    = Join-Path $repo $rel
        if (-not (Test-Path $full)) { throw "page-dates.json names '$rel' but the file is missing." }
        $html    = [System.IO.File]::ReadAllText($full)

        $rawTitle = ''
        $tm = [regex]::Match($html, '(?is)<title>(.*?)</title>')
        if ($tm.Success) { $rawTitle = Decode-Basic $tm.Groups[1].Value }
        if (-not $rawTitle) { throw "No <title> in '$rel' - refusing to build structured data without a headline." }

        $desc = ''
        $dm = [regex]::Match($html, '(?is)<meta\s+name="description"\s+content="(.*?)"')
        if ($dm.Success) { $desc = Decode-Basic $dm.Groups[1].Value }
        if (-not $desc) { throw "No meta description in '$rel'." }

        $url  = Page-Url  $rel
        $type = Page-Type $rel
        $pub  = $d.published
        $mod  = $d.modified

        $original = $html

        # ---- strip any previous fenced block so re-runs replace, not append --
        # The surrounding newlines are consumed too, so the rebuild below lands
        # the block in exactly the same bytes every time. An earlier version
        # left one newline behind per run, which grew the page on every pass.
        $html = [regex]::Replace($html, '(?s)[\r\n]*<!-- thaf-seo:begin -->.*?<!-- thaf-seo:end -->', '')

        # ---- take ownership of the tags this script generates ----------------
        # These were previously added only when absent, so every page kept the
        # first og:title and og:description it ever had. After the pages were
        # retitled, <title> and og:title disagreed about the same story, which
        # is exactly the contradiction a share or a search result surfaces.
        # Each owned tag is removed here and rebuilt from the page below, so
        # there is one source for each value and re-running cannot drift.
        foreach ($prop in @('og:site_name', 'og:type', 'og:title', 'og:description', 'og:url',
                'og:image', 'og:image:type', 'og:image:width', 'og:image:height', 'og:image:alt',
                'article:published_time', 'article:modified_time', 'article:section', 'article:author',
                'article:publisher')) {
            $html = [regex]::Replace($html, '(?is)<meta\s+property="' + [regex]::Escape($prop) + '"\s+content="[^"]*"\s*/?>\s*', '')
        }
        foreach ($nm in @('twitter:card', 'twitter:title', 'twitter:description',
                'twitter:image', 'twitter:image:alt', 'twitter:site', 'twitter:creator')) {
            $html = [regex]::Replace($html, '(?is)<meta\s+name="' + [regex]::Escape($nm) + '"\s+content="[^"]*"\s*/?>\s*', '')
        }

        $head = New-Object System.Collections.Generic.List[string]
        $head.Add('<!-- thaf-seo:begin -->')
        $head.Add('<!-- Generated by scripts/thaf-apply-metadata.ps1. Dates come from git history. -->')

        $have = { param($needle) return $html.Contains($needle) }
        $trail = Read-Trail $html
        $sectionName = if ($trail) { $trail.TopicName } else { Page-Section $rel }
        $ogAlt = Decode-Basic $rawTitle
        if (-not (& $have 'rel="canonical"')) {
            $head.Add('<link rel="canonical" href="' + (Esc $url) + '">')
        }
        if (-not (& $have 'property="og:site_name"')) {
            $head.Add('<meta property="og:site_name" content="' + (Esc $siteName) + '">')
        }
        if (-not (& $have 'property="og:type"')) {
            $ogType = if ($type -eq 'article' -or $type -eq 'evidence') { 'article' } else { 'website' }
            $head.Add('<meta property="og:type" content="' + $ogType + '">')
        }
        if (-not (& $have 'property="og:title"')) {
            $head.Add('<meta property="og:title" content="' + (Esc $rawTitle) + '">')
        }
        if (-not (& $have 'property="og:description"')) {
            $head.Add('<meta property="og:description" content="' + (Esc $desc) + '">')
        }
        if (-not (& $have 'property="og:url"')) {
            $head.Add('<meta property="og:url" content="' + (Esc $url) + '">')
        }
        if (-not (& $have 'property="og:image"')) {
            $head.Add('<meta property="og:image" content="' + $imgUrl + '">')
            $head.Add('<meta property="og:image:type" content="image/png">')
            $head.Add('<meta property="og:image:width" content="' + $imgW + '">')
            $head.Add('<meta property="og:image:height" content="' + $imgH + '">')
            $head.Add('<meta property="og:image:alt" content="' + (Esc $ogAlt) + '">')
        }
        if (($type -eq 'article' -or $type -eq 'evidence') -and -not (& $have 'property="article:published_time"')) {
            $head.Add('<meta property="article:published_time" content="' + $pub + '">')
            $head.Add('<meta property="article:modified_time" content="' + $mod + '">')
            $head.Add('<meta property="article:section" content="' + (Esc $sectionName) + '">')
        }
        if (-not (& $have 'name="twitter:card"')) {
            $head.Add('<meta name="twitter:card" content="summary_large_image">')
            $head.Add('<meta name="twitter:title" content="' + (Esc $rawTitle) + '">')
            $head.Add('<meta name="twitter:description" content="' + (Esc $desc) + '">')
            $head.Add('<meta name="twitter:image" content="' + $imgUrl + '">')
            $head.Add('<meta name="twitter:image:alt" content="' + (Esc $ogAlt) + '">')
        }

        # ---- JSON-LD ---------------------------------------------------------
        $org = [ordered]@{
            '@type' = 'NewsMediaOrganization'
            '@id'   = $publisherId
            name    = $siteName
            url     = "$origin/"
            logo    = [ordered]@{ '@type' = 'ImageObject'; url = $logoUrl; width = $logo.W; height = $logo.H }
        }
        # a share/lead image node, reused wherever schema.org wants one
        $imgNode = [ordered]@{
            '@type'  = 'ImageObject'
            url      = $imgUrl
            width    = $imgW
            height   = $imgH
            caption  = $ogAlt
        }
        $ld = $null
        switch ($type) {
            'article' {
                $ld = [ordered]@{
                    '@context'         = 'https://schema.org'
                    '@type'            = 'NewsArticle'
                    headline           = $rawTitle
                    description        = $desc
                    datePublished      = $pub
                    dateModified       = $mod
                    url                = $url
                    mainEntityOfPage   = [ordered]@{ '@type' = 'WebPage'; '@id' = $url }
                    image              = $imgNode
                    articleSection     = $sectionName
                    inLanguage         = 'en'
                    isAccessibleForFree = $true
                    author             = [ordered]@{ '@type' = 'Organization'; name = 'THE HUMANS ARE FINE newsroom'; url = "$origin/newsroom/" }
                    isPartOf           = [ordered]@{ '@type' = 'WebSite'; '@id' = "$origin/#website" }
                    publisher          = $org
                }
            }
            'evidence' {
                $ld = [ordered]@{
                    '@context'       = 'https://schema.org'
                    '@type'          = 'WebPage'
                    name             = $rawTitle
                    description      = $desc
                    image            = $imgNode
                    datePublished    = $pub
                    dateModified     = $mod
                    url              = $url
                    inLanguage       = 'en'
                    isPartOf         = [ordered]@{ '@type' = 'WebSite'; '@id' = "$origin/#website" }
                    publisher        = $org
                }
            }
            'home' {
                $ld = [ordered]@{
                    '@context' = 'https://schema.org'
                    '@graph'   = @(
                        [ordered]@{
                            '@type'      = 'WebSite'
                            '@id'        = "$origin/#website"
                            name         = $siteName
                            alternateName = 'The Humans Are Fine'
                            url          = "$origin/"
                            description  = $desc
                            image        = $imgNode
                            inLanguage   = 'en'
                            publisher    = [ordered]@{ '@id' = $publisherId }
                        },
                        $org
                    )
                }
            }
            default {
                $ld = [ordered]@{
                    '@context'    = 'https://schema.org'
                    '@type'       = if ($type -eq 'collection') { 'CollectionPage' } else { 'WebPage' }
                    name          = $rawTitle
                    description   = $desc
                    image         = $imgNode
                    url           = $url
                    datePublished = $pub
                    dateModified  = $mod
                    inLanguage    = 'en'
                    isPartOf      = [ordered]@{ '@type' = 'WebSite'; '@id' = "$origin/#website" }
                    publisher     = $org
                }
            }
        }
        $json = $ld | ConvertTo-Json -Depth 8 -Compress
        $head.Add('<script type="application/ld+json">' + $json + '</script>')

        # ---- BreadcrumbList, only where the trail is visible -----------------
        if ($trail) {
            $topicUrl = "$origin/" + $trail.TopicRel
            $crumbs = [ordered]@{
                '@context'        = 'https://schema.org'
                '@type'           = 'BreadcrumbList'
                itemListElement   = @(
                    [ordered]@{ '@type' = 'ListItem'; position = 1; name = 'Home'; item = "$origin/" },
                    [ordered]@{ '@type' = 'ListItem'; position = 2; name = $trail.TopicName; item = $topicUrl },
                    [ordered]@{ '@type' = 'ListItem'; position = 3; name = $trail.HereLabel; item = $url }
                )
            }
            $head.Add('<script type="application/ld+json">' + ($crumbs | ConvertTo-Json -Depth 6 -Compress) + '</script>')
        }
        $head.Add('<!-- thaf-seo:end -->')

        $block = "`r`n" + ($head -join "`r`n") + "`r`n"

        $idx = $html.IndexOf('</head>')
        if ($idx -lt 0) { throw "No </head> in '$rel'." }
        $new = $html.Substring(0, $idx) + $block + $html.Substring($idx)

        if ($new -eq $original) { $skipped++; continue }
        if (-not $WhatIf) {
            $enc = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($full, $new, $enc)
        }
        $changed++
    }

    Write-Output ("changed={0} unchanged={1} whatIf={2}" -f $changed, $skipped, [bool]$WhatIf)
}
finally {
    Pop-Location
}
