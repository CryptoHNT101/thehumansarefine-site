# ============================================================================
# THE HUMANS ARE FINE - local link, asset and page-weight check
#
# Checks the pages as they exist in this working tree (Release 2 is not
# deployed, so a live crawl would only re-prove that production is old).
# Every href/src that points inside the site must resolve to a tracked file;
# every link that leaves the site must be http(s). No network calls.
# ============================================================================
param([int]$HeavyKb = 250)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    $tracked = @(git ls-files) | ForEach-Object { $_.Trim() }
    $pages = @($tracked | Where-Object { $_ -like '*.html' })
    $fail = 0; $warn = 0; $checks = 0

    # Publication dates: markup, feed and visible page must all say one thing.
    $datesPath = Join-Path $repo 'scripts/page-dates.json'
    if (-not (Test-Path $datesPath)) { throw ("Missing dates file: " + $datesPath) }
    $pageDates = @{}
    foreach ($r in (Get-Content $datesPath -Raw -Encoding UTF8 | ConvertFrom-Json)) { $pageDates[$r.path] = $r }

    function Fail($m) { $script:fail++; Write-Output "FAIL  $m" }
    function Warn($m) { $script:warn++; Write-Output "WARN  $m" }
    function Pass($m) { }

    foreach ($rel in $pages) {
        $html = [IO.File]::ReadAllText((Join-Path $repo $rel))
        $dir = Split-Path $rel -Parent
        if (-not $dir) { $dir = '.' }

        # ---- internal references ------------------------------------------
        foreach ($m in [regex]::Matches($html, '(?i)(?:href|src)\s*=\s*"([^"]+)"')) {
            $u = $m.Groups[1].Value.Trim()
            if ($u -eq '' -or $u.StartsWith('#') -or $u.StartsWith('data:') -or $u.StartsWith('mailto:')) { continue }
            if ($u -match '^(https?:)?//') { continue }   # external, counted below
            $checks++
            $pathOnly = ($u -split '[?#]')[0]
            if ($pathOnly -eq '') { continue }
            $target = if ($pathOnly.StartsWith('/')) { $pathOnly.TrimStart('/') }
                      else { [IO.Path]::GetFullPath((Join-Path (Join-Path $repo $dir) $pathOnly)).Substring($repo.Length).TrimStart('\', '/') }
            $target = $target -replace '\\', '/'
            if ($target -eq '' -or $target.EndsWith('/')) { $target = $target + 'index.html' }
            if (-not (Test-Path (Join-Path $repo $target))) { Fail "$rel : broken internal reference '$u' -> $target" }
            elseif ($tracked -notcontains $target) { Fail "$rel : references an untracked file '$u' -> $target (404 after deploy)" }
        }

        # ---- external links use a real scheme ------------------------------
        foreach ($m in [regex]::Matches($html, '(?i)<a\s[^>]*href\s*=\s*"//[^"]+"')) {
            Fail "$rel : protocol-relative link is fragile offline: $($m.Value)"
        }

        # ---- one <h1>, a title, a canonical ---------------------------------
        $checks++
        $h1 = ([regex]::Matches($html, '(?i)<h1[\s>]')).Count
        if ($h1 -ne 1) { Fail "$rel : $h1 <h1> elements (expected 1)" }
        if ($html -notmatch '(?i)<link\s+rel="canonical"') { Fail "$rel : no canonical link" }
        if ($html -notmatch '(?i)<meta\s+property="og:image"') { Fail "$rel : no og:image" }

        # ---- weight --------------------------------------------------------
        $bytes = (Get-Item (Join-Path $repo $rel)).Length
        $kb = [Math]::Round($bytes / 1KB, 1)
        $checks++
        if ($kb -gt $HeavyKb) { Warn "$rel : HTML alone is $kb KB (over $HeavyKb KB)" }

        # ---- inline <script> size (the analytics + nav bundle is inline) ----
        $inline = 0
        foreach ($m in [regex]::Matches($html, '(?is)<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>')) { $inline += $m.Groups[1].Value.Length }
        if ($inline -gt 60000) { Warn "$rel : $([Math]::Round($inline/1KB,1)) KB of inline script" }

        # ---- duplicate meta tags (a real risk after generated blocks) ------
        foreach ($name in @('description', 'viewport', 'charset')) {
            $c = ([regex]::Matches($html, '(?i)<meta\s+(?:name|charset)\s*=?\s*"?' + $name + '"')).Count
            if ($c -gt 1) { Warn "$rel : $c '$name' meta declarations" }
        }
        foreach ($prop in @('og:title','og:description','og:url','og:image','og:type')) {
            $c = ([regex]::Matches($html, '(?i)<meta\s+property="' + [regex]::Escape($prop) + '"')).Count
            if ($c -ne 1) { Fail "$rel : $c declarations of $prop (expected 1)" }
        }
        # A page carries one structured-data block, plus a second BreadcrumbList
        # block when it displays a breadcrumb trail. Anything beyond that is
        # duplication, and every block has to be valid JSON with an @type.
        $blocks = [regex]::Matches($html, '(?is)<script\s+type="application/ld\+json">(.*?)</script>')
        if ($blocks.Count -lt 1 -or $blocks.Count -gt 2) { Fail "$rel : $($blocks.Count) JSON-LD blocks (expected 1, or 2 with a breadcrumb list)" }
        $types = @()
        foreach ($b in $blocks) {
            try { $obj = $b.Groups[1].Value | ConvertFrom-Json } catch { Fail "$rel : JSON-LD block does not parse - $($_.Exception.Message)"; continue }
            if (-not $obj.'@type' -and -not $obj.'@graph') { Fail "$rel : JSON-LD block has neither @type nor @graph" }
            $types += $obj.'@type'
            if ($obj.'@type' -eq 'NewsArticle' -or $obj.'@type' -eq 'Article') {
                $checks++
                if (-not $pageDates.ContainsKey($rel)) { Fail "$rel : structured data has dates but the page has no git date on record" }
                else {
                    $want = [datetimeoffset]::Parse($pageDates[$rel].published, [Globalization.CultureInfo]::InvariantCulture)
                    $got = $null
                    try { $got = [datetimeoffset]::Parse([string]$obj.datePublished, [Globalization.CultureInfo]::InvariantCulture) } catch { Fail "$rel : datePublished is not a parsable date" }
                    if ($got -and $got.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss') -ne $want.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss')) {
                        Fail "$rel : datePublished $($obj.datePublished) does not match git publication $($pageDates[$rel].published)"
                    }
                    if ($got) {
                        $label = $got.ToString('MMMM d, yyyy', [Globalization.CultureInfo]::InvariantCulture)
                        if ($html -notmatch ("<li><b>Published</b> " + [regex]::Escape($label))) {
                            Fail "$rel : reader cannot see the publication date ($label) that the markup claims"
                        }
                    }
                }
            }
        }
        if ($blocks.Count -eq 2 -and $types -notcontains 'BreadcrumbList') { Fail "$rel : two JSON-LD blocks and neither is a BreadcrumbList" }

        # A breadcrumb list is a promise to a search engine about the page's place
        # in the site. It has to be walkable: positions counted from 1 with no
        # gaps, absolute URLs, and a last crumb that IS this page. Anything else is
        # markup a crawler will discard, so it is checked rather than assumed.
        $canonMatch = [regex]::Match($html, '(?is)<link\s+rel="canonical"\s+href="([^"]+)"')
        $canon = ''
        if ($canonMatch.Success) { $canon = $canonMatch.Groups[1].Value }
        if ($canon -eq '') { Fail "$rel : no canonical URL" }
        foreach ($b in $blocks) {
            if ($b.Groups[1].Value -notmatch '"BreadcrumbList"') { continue }
            $checks++
            try { $bc = $b.Groups[1].Value | ConvertFrom-Json } catch { continue }
            $items = @($bc.itemListElement)
            if ($items.Count -lt 2) { Fail "$rel : breadcrumb list has $($items.Count) item(s)" }
            for ($i = 0; $i -lt $items.Count; $i++) {
                if ([int]$items[$i].position -ne ($i + 1)) { Fail "$rel : breadcrumb position $($items[$i].position) where $($i + 1) was due" }
                $itemUrl = [string]$items[$i].item
                if ($itemUrl -notmatch '^https://www\.thehumansarefine\.com/') { Fail "$rel : breadcrumb item '$itemUrl' is not an absolute on-site URL" }
            }
            if ($canon -ne '' -and [string]$items[$items.Count - 1].item -ne $canon) {
                Fail "$rel : last breadcrumb does not point at the canonical URL"
            }
        }

        # Social card numbers have to match the file that is actually served, or a
        # crawler reserves the wrong box and crops the card.
        $checks++
        $ogW = [regex]::Match($html, '(?i)<meta\s+property="og:image:width"\s+content="(\d+)"')
        $ogH = [regex]::Match($html, '(?i)<meta\s+property="og:image:height"\s+content="(\d+)"')
        $ogU = [regex]::Match($html, '(?i)<meta\s+property="og:image"\s+content="([^"]+)"')
        $twCard = [regex]::Match($html, '(?i)<meta\s+name="twitter:card"\s+content="([^"]+)"')
        if (-not $ogW.Success -or -not $ogH.Success) { Fail "$rel : og:image declares no width/height" }
        if (-not $twCard.Success -or $twCard.Groups[1].Value -ne 'summary_large_image') { Fail "$rel : twitter:card is not summary_large_image" }
        if ($ogU.Success) {
            # Resolve the URL as written to a path inside the deploy tree. The old version
            # did 'assets/' + basename, which silently discarded the subdirectory:
            # cards moved to assets/social/ were reported missing though present.
            $imgUrl = $ogU.Groups[1].Value
            $imgRel = ($imgUrl -replace '^https?://[^/]+/', '' -replace '^/', '')
            $imgPath = Join-Path $repo $imgRel
            if (-not (Test-Path $imgPath)) { Fail "$rel : og:image file $imgRel does not exist" }
            elseif ($ogW.Success -and $ogH.Success) {
                # PNG only: the IHDR chunk carries width and height at bytes 16..23.
                $bytes = [IO.File]::ReadAllBytes($imgPath)
                if ($bytes.Length -gt 24 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) {
                    $realW = ([int]$bytes[16] -shl 24) + ([int]$bytes[17] -shl 16) + ([int]$bytes[18] -shl 8) + [int]$bytes[19]
                    $realH = ([int]$bytes[20] -shl 24) + ([int]$bytes[21] -shl 16) + ([int]$bytes[22] -shl 8) + [int]$bytes[23]
                    if ($realW -ne [int]$ogW.Groups[1].Value -or $realH -ne [int]$ogH.Groups[1].Value) {
                        Fail "$rel : og:image says $($ogW.Groups[1].Value)x$($ogH.Groups[1].Value) but $imgRel is ${realW}x${realH}"
                    }
                }
                else { Warn "$rel : og:image $imgRel is not a PNG this check can measure" }
            }
        }
    }

    # ---- every tracked asset is referenced somewhere -----------------------
    foreach ($a in @($tracked | Where-Object { $_ -like 'assets/*' })) {
        $name = Split-Path $a -Leaf
        $used = $false
        foreach ($p in $pages) {
            if ([IO.File]::ReadAllText((Join-Path $repo $p)).Contains($name)) { $used = $true; break }
        }
        if (-not $used) { Warn "asset $a is tracked but no page references it" }
    }

    Write-Output ''
    Write-Output ("pages={0}  checks={1}  PASS={2}  FAIL={3}  WARN={4}" -f $pages.Count, $checks, ($checks - $fail), $fail, $warn)
    if ($fail -gt 0) { Write-Output 'VERDICT: FAIL'; exit 1 } else { Write-Output 'VERDICT: PASS'; exit 0 }
}
finally { Pop-Location }
