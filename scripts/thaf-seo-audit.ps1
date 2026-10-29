# ============================================================================
# THE HUMANS ARE FINE - search / integrity audit
#
# Replaces tools/validate_site.ps1, which asserts a design the newspaper no
# longer uses and therefore reports FAIL on a healthy site. Every check here
# runs against the files actually in this repository.
#
# Read-only. Writes nothing except the optional -JsonOut summary.
# Exit code 0 = all checks pass, 1 = at least one FAIL.
# ============================================================================
param(
    [string]$JsonOut = ''
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
$script:pass = 0
$script:fail = 0
$script:warn = 0
$script:failures = New-Object System.Collections.Generic.List[string]

function Pass([string]$m) { $script:pass++; Write-Output ("PASS  " + $m) }
function Fail([string]$m) { $script:fail++; $script:failures.Add($m); Write-Output ("FAIL  " + $m) }
function Warn([string]$m) { $script:warn++; Write-Output ("WARN  " + $m) }

try {
    $origin = 'https://www.thehumansarefine.com'
    $tracked = @(git ls-files) | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    $pages = @($tracked | Where-Object { $_ -like '*.html' })
    if ($pages.Count -eq 0) { throw 'No tracked HTML pages found.' }
    Write-Output ("Tracked files: {0}   HTML pages: {1}" -f $tracked.Count, $pages.Count)
    Write-Output ''

    function Page-Url([string]$rel) {
        if ($rel -eq 'index.html') { return "$origin/" }
        if ($rel -match '^(.*/)index\.html$') { return "$origin/$($Matches[1])" }
        return "$origin/$rel"
    }

    $titles = @{}
    $descs  = @{}
    $meta   = @{}

    # ---------------- per-page checks ------------------------------------
    foreach ($rel in $pages) {
        $full = Join-Path $repo $rel
        $html = [IO.File]::ReadAllText($full)
        Write-Output ("--- " + $rel)

        $t = [regex]::Match($html, '(?is)<title>(.*?)</title>')
        if (-not $t.Success -or [string]::IsNullOrWhiteSpace($t.Groups[1].Value)) {
            Fail "$rel`: no <title>"
            $title = ''
        } else {
            $title = $t.Groups[1].Value.Trim()
            if ($title.Length -lt 15) { Fail "$rel`: title too short ({0} chars)" -f $title.Length }
            elseif ($title.Length -gt 90) { Warn ("$rel`: title long ({0} chars)" -f $title.Length) }
            else { Pass "$rel`: title present ($($title.Length) chars)" }
            if ($titles.ContainsKey($title)) { Fail "$rel`: duplicate title (also $($titles[$title]))" }
            else { $titles[$title] = $rel }
        }

        $d = [regex]::Match($html, '(?is)<meta\s+name="description"\s+content="(.*?)"')
        if (-not $d.Success) { Fail "$rel`: no meta description"; $desc = '' }
        else {
            $desc = $d.Groups[1].Value.Trim()
            if ($desc.Length -lt 60) { Fail ("$rel`: description short ({0} chars, search snippets need ~120-160)" -f $desc.Length) }
            elseif ($desc.Length -gt 175) { Warn ("$rel`: description long ({0} chars)" -f $desc.Length) }
            else { Pass "$rel`: description present ($($desc.Length) chars)" }
            if ($descs.ContainsKey($desc)) { Fail "$rel`: duplicate description (also $($descs[$desc]))" }
            else { $descs[$desc] = $rel }
        }

        $expected = Page-Url $rel
        $c = [regex]::Match($html, '(?is)<link\s+rel="canonical"\s+href="([^"]+)"')
        if (-not $c.Success) { Fail "$rel`: no canonical" }
        elseif ($c.Groups[1].Value.Trim() -ne $expected) { Fail "$rel`: canonical is '$($c.Groups[1].Value)' but page URL is '$expected'" }
        else { Pass "$rel`: canonical matches page URL" }

        foreach ($prop in 'og:title', 'og:description', 'og:url', 'og:image', 'og:type') {
            if ($html -match ('property="' + [regex]::Escape($prop) + '"')) { Pass "$rel`: $prop" }
            else { Fail "$rel`: missing $prop" }
        }
        if ($html -match 'name="twitter:card"') { Pass "$rel`: twitter:card" } else { Fail "$rel`: missing twitter:card" }
        if ($html -match 'name="viewport"') { Pass "$rel`: viewport" } else { Fail "$rel`: no viewport" }

        # JSON-LD
        $lds = [regex]::Matches($html, '(?is)<script type="application/ld\+json">(.*?)</script>')
        if ($lds.Count -eq 0) { Fail "$rel`: no JSON-LD structured data" }
        else {
            $ok = $true
            foreach ($ld in $lds) {
                try { $null = $ld.Groups[1].Value | ConvertFrom-Json }
                catch { Fail "$rel`: JSON-LD is not valid JSON"; $ok = $false }
            }
            if ($ok) {
                $json = $lds[0].Groups[1].Value
                $isArticle = $rel -match '^articles/' -and $rel -notmatch '-evidence\.html$'
                if ($isArticle) {
                    foreach ($need in 'datePublished', 'dateModified', 'headline', 'author', 'publisher', 'mainEntityOfPage') {
                        if ($json -match ('"' + $need + '"')) { Pass "$rel`: NewsArticle.$need" }
                        else { Fail "$rel`: NewsArticle missing $need" }
                    }
                } else { Pass "$rel`: JSON-LD valid JSON" }
            }
        }

        # internal link resolution
        $bad = @()
        foreach ($m in [regex]::Matches($html, '(?i)href="([^"#?]+?\.html)"')) {
            $href = $m.Groups[1].Value.Trim()
            if ($href -match '^(https?:|mailto:|//)') { continue }
            $target = $href
            if ($target.StartsWith('/')) { $target = $target.Substring(1) }
            $candidate = if ($rel -match '^(.*/)') { [IO.Path]::GetFullPath((Join-Path $repo (Join-Path $Matches[1] $target))) } else { [IO.Path]::GetFullPath((Join-Path $repo $target)) }
            if (-not (Test-Path $candidate)) { $bad += $href }
            else {
                $relc = $candidate.Substring($repo.Length).TrimStart('\', '/').Replace('\', '/')
                if ($tracked -notcontains $relc) { $bad += ("$href (exists but is NOT tracked - will 404 in production)") }
            }
        }
        if ($bad.Count -eq 0) { Pass "$rel`: all internal links resolve to tracked files" }
        else { Fail ("$rel`: {0} unresolved internal link(s): {1}" -f $bad.Count, (($bad | Select-Object -Unique) -join '; ')) }

        $meta[$rel] = [pscustomobject]@{ title = $title; description = $desc }
    }

    Write-Output ''
    Write-Output '--- sitemap.xml'

    [xml]$sm = Get-Content 'sitemap.xml' -Raw -Encoding UTF8
    $ns = New-Object System.Xml.XmlNamespaceManager($sm.NameTable)
    $ns.AddNamespace('s', 'http://www.sitemaps.org/schemas/sitemap/0.9')
    $urls = @($sm.SelectNodes('//s:url', $ns))
    if ($urls.Count -eq 0) { Fail 'sitemap.xml contains no <url> entries' }
    else { Pass "sitemap.xml is well-formed XML with $($urls.Count) URLs" }

    $locs = @()
    foreach ($u in $urls) {
        $loc = $u.SelectSingleNode('s:loc', $ns).InnerText.Trim()
        $last = $u.SelectSingleNode('s:lastmod', $ns)
        $locs += $loc
        $relPath = $loc.Substring($origin.Length).TrimStart('/')
        if ($relPath -eq '' -or $relPath.EndsWith('/')) { $relPath = $relPath + 'index.html' }
        if ($tracked -notcontains $relPath) { Fail "sitemap advertises '$loc' but '$relPath' is not a tracked page (it will 404)" }
        elseif (-not $last) { Fail "sitemap entry '$loc' has no <lastmod>" }
        else { Pass "sitemap: $loc (lastmod $($last.InnerText))" }
    }
    foreach ($rel in $pages) {
        if ($rel -match '-evidence\.html$') { continue }   # evidence files are linked from articles, not a crawl entry point
        $u = Page-Url $rel
        if ($locs -notcontains $u) { Warn "page not in sitemap: $u" }
    }

    Write-Output ''
    Write-Output '--- rss.xml'
    # Parsed with regex rather than the XML adapter: guid carries an
    # isPermaLink attribute, and the adapter returns the element object rather
    # than its text, which produced false guid mismatches on a valid feed.
    $rssRaw = Get-Content 'rss.xml' -Raw -Encoding UTF8
    [xml]$rssCheck = $rssRaw
    $itemBlocks = [regex]::Matches($rssRaw, '(?s)<item>(.*?)</item>')
    if ($itemBlocks.Count -le 0) { Fail 'rss.xml has no <item> elements' }
    else { Pass "rss.xml is well-formed XML with $($itemBlocks.Count) items" }
    foreach ($b in $itemBlocks) {
        $blk  = $b.Groups[1].Value
        $link = [regex]::Match($blk, '<link>(.*?)</link>').Groups[1].Value.Trim()
        $pd   = [regex]::Match($blk, '<pubDate>(.*?)</pubDate>').Groups[1].Value.Trim()
        $guid = [regex]::Match($blk, '<guid[^>]*>(.*?)</guid>').Groups[1].Value.Trim()
        $de   = [regex]::Match($blk, '(?s)<description>(.*?)</description>').Groups[1].Value.Trim()
        $ti   = [regex]::Match($blk, '(?s)<title>(.*?)</title>').Groups[1].Value.Trim()
        $label = $ti.Substring(0, [Math]::Min(46, $ti.Length))
        $relPath = $link.Substring($origin.Length).TrimStart('/')

        if ($tracked -notcontains $relPath) { Fail "rss item links to untracked page: $link" }
        elseif ([string]::IsNullOrWhiteSpace($pd)) { Fail "rss item has no pubDate: $link" }
        else { Pass "rss: $label...  $pd" }

        if ($guid -eq '') { Fail "rss item has no guid: $link" }
        elseif ($guid -ne $link) { Fail "rss guid does not match link: $link" }
        else { Pass "rss guid permalink matches: $label" }

        if ($de.Length -lt 40) { Fail ("rss item description is empty or too short ({0} chars): {1}" -f $de.Length, $link) }
        else { Pass ("rss description present ({0} chars): {1}" -f $de.Length, $label) }
    }

    Write-Output ''
    Write-Output '--- robots.txt'
    $robots = Get-Content 'robots.txt' -Raw -Encoding UTF8
    if ($robots -match 'Sitemap:\s*\S+sitemap\.xml') { Pass 'robots.txt declares the sitemap' } else { Fail 'robots.txt does not declare a sitemap' }
    foreach ($m in [regex]::Matches($robots, '(?im)^Disallow:\s*(\S+)')) {
        $p = $m.Groups[1].Value.Trim()
        if ($p -eq '/') { Fail 'robots.txt disallows the whole site' ; continue }
        foreach ($rel in $pages) {
            if ($rel.StartsWith($p.TrimStart('/'))) { Fail "robots.txt Disallow $p blocks a tracked public page: $rel" }
        }
    }
    if ($robots -notmatch 'Disallow: /articles/') { Pass 'robots.txt does not block the article archive' }

    Write-Output ''
    Write-Output '============================================'
    Write-Output ("PASS={0}  FAIL={1}  WARN={2}" -f $script:pass, $script:fail, $script:warn)
    if ($script:fail -eq 0) { Write-Output 'VERDICT: PASS'; $code = 0 }
    else { Write-Output 'VERDICT: FAIL'; Write-Output 'Failures:'; $script:failures | ForEach-Object { Write-Output ("  - " + $_) }; $code = 1 }

    if ($JsonOut) {
        [pscustomobject]@{
            generated  = (Get-Date).ToString('o')
            pass       = $script:pass
            fail       = $script:fail
            warn       = $script:warn
            failures   = $script:failures
            pages      = $meta
        } | ConvertTo-Json -Depth 6 | Set-Content -Path $JsonOut -Encoding UTF8
        Write-Output ("summary written to " + $JsonOut)
    }
    exit $code
}
finally {
    Pop-Location
}
