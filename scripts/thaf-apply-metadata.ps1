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
# ============================================================================
param(
    [string]$DatesFile = 'page-dates.json',
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
    $bytes = [System.IO.File]::ReadAllBytes($imgPath)
    if (-not ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50)) { throw 'thaf-flagship-profile.png is not a PNG.' }
    $imgW = [int]$bytes[16] * 16777216 + [int]$bytes[17] * 65536 + [int]$bytes[18] * 256 + [int]$bytes[19]
    $imgH = [int]$bytes[20] * 16777216 + [int]$bytes[21] * 65536 + [int]$bytes[22] * 256 + [int]$bytes[23]
    $imgUrl = "$origin/assets/thaf-flagship-profile.png"
    Write-Output ("og:image = {0} ({1}x{2}, {3} bytes)" -f $imgUrl, $imgW, $imgH, $bytes.Length)

    function Decode-Basic([string]$s) {
        if ($null -eq $s) { return '' }
        $s = $s -replace '&mdash;', [char]0x2014
        $s = $s -replace '&ndash;', [char]0x2013
        $s = $s -replace '&amp;', '&'
        $s = $s -replace '&quot;', '"'
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

        $head = New-Object System.Collections.Generic.List[string]
        $head.Add('<!-- thaf-seo:begin -->')
        $head.Add('<!-- Generated by scripts/thaf-apply-metadata.ps1. Dates come from git history. -->')

        $have = { param($needle) return $html.Contains($needle) }
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
            $head.Add('<meta property="og:image:alt" content="THE HUMANS ARE FINE masthead mark">')
        }
        if (($type -eq 'article' -or $type -eq 'evidence') -and -not (& $have 'property="article:published_time"')) {
            $head.Add('<meta property="article:published_time" content="' + $pub + '">')
            $head.Add('<meta property="article:modified_time" content="' + $mod + '">')
            $head.Add('<meta property="article:section" content="' + (Esc (Page-Section $rel)) + '">')
        }
        if (-not (& $have 'name="twitter:card"')) {
            $head.Add('<meta name="twitter:card" content="summary_large_image">')
            $head.Add('<meta name="twitter:title" content="' + (Esc $rawTitle) + '">')
            $head.Add('<meta name="twitter:description" content="' + (Esc $desc) + '">')
            $head.Add('<meta name="twitter:image" content="' + $imgUrl + '">')
        }

        # ---- JSON-LD ---------------------------------------------------------
        $org = [ordered]@{
            '@type' = 'NewsMediaOrganization'
            '@id'   = $publisherId
            name    = $siteName
            url     = "$origin/"
            logo    = [ordered]@{ '@type' = 'ImageObject'; url = $imgUrl }
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
                    articleSection     = (Page-Section $rel)
                    inLanguage         = 'en'
                    isAccessibleForFree = $true
                    author             = [ordered]@{ '@type' = 'Organization'; name = 'THE HUMANS ARE FINE newsroom'; url = "$origin/newsroom/" }
                    publisher          = $org
                }
            }
            'evidence' {
                $ld = [ordered]@{
                    '@context'       = 'https://schema.org'
                    '@type'          = 'WebPage'
                    name             = $rawTitle
                    description      = $desc
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
