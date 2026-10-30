# ============================================================================
# THE HUMANS ARE FINE - verify the discovery artifacts against the pages
#
# This is the gate. It does not check that files exist; it checks that they
# agree with each other, because the failure mode that matters is a sitemap or
# a share card that describes a page that has since changed.
#
# Exit code is 0 only if every assertion passes.
# ============================================================================
param(
    [string]$Origin = 'https://www.thehumansarefine.com'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Web
Add-Type -AssemblyName System.Drawing

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
$pass = 0; $fail = 0
function Ok($msg) { Write-Output "PASS  $msg"; $script:pass++ }
function Bad($msg) { Write-Output "FAIL  $msg"; $script:fail++ }

try {
    $tracked = @(git ls-files) | ForEach-Object { $_.Trim() }
    $articles = @($tracked | Where-Object { $_ -like 'articles/*.html' -and $_ -notlike '*-evidence.html' })
    if ($articles.Count -eq 0) { Bad 'no articles found' }

    foreach ($rel in $articles) {
        $slug = ($rel -replace '^articles/', '' -replace '\.html$', '')
        $html = [System.IO.File]::ReadAllText((Join-Path $repo $rel))

        # --- share card exists and is the size we claim in the meta tags ---
        $card = Join-Path $repo "assets\social\$slug.png"
        if (-not (Test-Path $card)) { Bad "$slug : social card missing" }
        else {
            $img = [System.Drawing.Image]::FromFile($card)
            if ($img.Width -ne 1200 -or $img.Height -ne 630) { Bad ("$slug : card is {0}x{1}, meta claims 1200x630" -f $img.Width, $img.Height) }
            $img.Dispose()

            $want = "$Origin/assets/social/$slug.png"
            $og = [regex]::Match($html, '<meta\s+property="og:image"\s+content="([^"]+)"')
            $tw = [regex]::Match($html, '<meta\s+name="twitter:image"\s+content="([^"]+)"')
            if ($og.Success -and $og.Groups[1].Value -eq $want) { Ok "$slug : og:image points at its own card" } else { Bad "$slug : og:image is '$($og.Groups[1].Value)' not '$want'" }
            if ($tw.Success -and $tw.Groups[1].Value -eq $want) { Ok "$slug : twitter:image matches" } else { Bad "$slug : twitter:image mismatch" }

            # The card must be the one that actually corresponds to this page:
            # rebuild it in memory is overkill, so instead assert the alt text
            # names this article's own headline.
            $h1 = [System.Web.HttpUtility]::HtmlDecode([regex]::Replace([regex]::Match($html, '(?is)<h1[^>]*>(.*?)</h1>').Groups[1].Value, '<[^>]+>', '')).Trim()
            $alt = [regex]::Match($html, '<meta\s+property="og:image:alt"\s+content="([^"]*)"')
            if ($alt.Success -and -not [string]::IsNullOrWhiteSpace($alt.Groups[1].Value)) {
                Ok "$slug : og:image:alt present"
            } else { Bad "$slug : og:image:alt missing or empty" }
            # The attribute holds XML-escaped text (&apos; etc), so decode before
            # comparing it with the headline or every apostrophe reads as a mismatch.
            $altText = if ($alt.Success) { [System.Web.HttpUtility]::HtmlDecode($alt.Groups[1].Value.Trim()) } else { '' }
            if ($altText -ne '' -and $altText -notmatch [regex]::Escape($h1.Substring(0, [Math]::Min(25, $h1.Length)))) {
                Bad "$slug : og:image:alt does not describe this article's headline (alt='$altText')"
            } elseif ($altText -ne '') {
                Ok "$slug : og:image:alt names this article's headline"
            }
        }

        # --- deep preview permission ---
        $rob = [regex]::Match($html, '<meta\s+name="robots"\s+content="([^"]+)"')
        if ($rob.Success -and $rob.Groups[1].Value -match 'max-image-preview:large') { Ok "$slug : permits large image previews" }
        else { Bad "$slug : max-image-preview:large absent" }

        # --- disclosure present exactly once and pointing at a real file ---
        $count = ([regex]::Matches($html, 'thaf:ai-disclosure')).Count
        if ($count -eq 1) { Ok "$slug : disclosure appears once" } else { Bad "$slug : disclosure count = $count" }
        if ($html -match 'AI agents operating under human editorial authority') { Ok "$slug : states AI authorship in the body" }
        else { Bad "$slug : no AI authorship statement in the body" }
        $evLink = "articles\$slug-evidence.html"
        if (Test-Path (Join-Path $repo $evLink)) { Ok "$slug : disclosure links to an Evidence File that exists" }
        else { Bad "$slug : disclosure links to a missing Evidence File ($evLink)" }

        # --- structured data still parses after the edits ---
        $blocks = [regex]::Matches($html, '(?is)<script type="application/ld\+json">(.*?)</script>')
        $types = @(); $parseError = $false; $news = $null
        foreach ($b in $blocks) {
            try { $o = $b.Groups[1].Value | ConvertFrom-Json } catch { $parseError = $true; continue }
            if ($o.'@type') { $types += $o.'@type' }
            if ($o.'@type' -eq 'NewsArticle') { $news = $o }
        }
        if ($parseError) { Bad "$slug : an ld+json block no longer parses" }
        if ($types -contains 'NewsArticle') { Ok "$slug : NewsArticle block intact" } else { Bad "$slug : NewsArticle block missing" }
        if ($news -and $news.image.url -eq "$Origin/assets/social/$slug.png") { Ok "$slug : NewsArticle.image is its own card" }
        elseif ($news) { Bad "$slug : NewsArticle.image is '$($news.image.url)'" }
        foreach ($field in @('headline', 'datePublished', 'dateModified', 'author', 'publisher')) {
            if (-not $news.$field) { Bad "$slug : NewsArticle.$field missing" }
        }

        # --- anchor integrity: the whole page still closes cleanly ---
        if (([regex]::Matches($html, '</article>')).Count -eq 1) { Ok "$slug : single </article> preserved" }
        else { Bad "$slug : </article> count is wrong" }
    }

    # --- news sitemap agrees with the pages ---
    $newsPath = Join-Path $repo 'news-sitemap.xml'
    if (-not (Test-Path $newsPath)) { Bad 'news-sitemap.xml missing' }
    else {
        [xml]$nx = Get-Content $newsPath -Raw -Encoding UTF8
        $ns = New-Object System.Xml.XmlNamespaceManager($nx.NameTable)
        $ns.AddNamespace('s', 'http://www.sitemaps.org/schemas/sitemap/0.9')
        $ns.AddNamespace('n', 'http://www.google.com/schemas/sitemap-news/0.9')
        $entries = @($nx.SelectNodes('//s:url', $ns))
        Ok ("news sitemap parses with {0} entries" -f $entries.Count)
        foreach ($e in $entries) {
            $loc = $e.SelectSingleNode('s:loc', $ns).InnerText
            $relLocal = $loc.Replace("$Origin/", '')
            if (Test-Path (Join-Path $repo $relLocal)) { Ok "news entry resolves: $relLocal" } else { Bad "news entry points at a missing page: $relLocal" }
            if ($relLocal -like '*-evidence.html') { Bad "Evidence File in news sitemap: $relLocal" }
        }
        $claimed = @($entries | ForEach-Object { $_.SelectSingleNode('n:news/n:publication_date', $ns).InnerText })
        foreach ($c in $claimed) {
            $d = [datetimeoffset]::Parse($c, [System.Globalization.CultureInfo]::InvariantCulture)
            $ageHours = ([datetimeoffset]::Now - $d).TotalHours
            if ($ageHours -gt 48) { Bad "news entry is $([int]$ageHours)h old, outside Google's two-day window" }
        }
    }

    # --- robots advertises both sitemaps ---
    $robots = [System.IO.File]::ReadAllText((Join-Path $repo 'robots.txt'))
    if ($robots -match [regex]::Escape("Sitemap: $Origin/sitemap.xml")) { Ok 'robots.txt advertises sitemap.xml' } else { Bad 'robots.txt missing sitemap.xml line' }
    if ($robots -match [regex]::Escape("Sitemap: $Origin/news-sitemap.xml")) { Ok 'robots.txt advertises news-sitemap.xml' } else { Bad 'robots.txt missing news-sitemap.xml line' }
    if ($robots -match '\*\s*$' -and $robots -match 'User-agent: \*') { Ok 'robots.txt keeps a single wildcard user-agent block' }

    # --- standard sitemap still parses ---
    try {
        [xml]$sx = Get-Content (Join-Path $repo 'sitemap.xml') -Raw -Encoding UTF8
        Ok ("sitemap.xml parses with {0} URLs" -f @($sx.urlset.url).Count)
    } catch { Bad "sitemap.xml no longer parses: $($_.Exception.Message)" }

    # --- markup sanity: no stray '>' runs after an attribute ------------------
    # Added after a real escape: eight article pages shipped with '">>>' appended
    # to their og:image and twitter:image tags. Every other assertion in this file
    # passed, because each of them reads a value out of a regex that tolerates the
    # trailing junk. The malformed markup was invisible to the gate.
    $gtBad = @()
    foreach ($rel in @($tracked | Where-Object { $_ -like '*.html' })) {
        $p = Join-Path $repo ($rel -replace '/', '\')
        if (-not (Test-Path $p)) { continue }
        $h = [System.IO.File]::ReadAllText($p)
        $n = [regex]::Matches($h, 'content="[^"]*">>').Count
        $m = [regex]::Matches($h, '>\s*>>').Count
        if ($n -gt 0 -or $m -gt 0) { $gtBad += "$rel ($n attribute, $m tag)" }
    }
    if ($gtBad.Count -eq 0) { Ok 'no stray > runs after attributes in any page' }
    else { Bad ("stray > runs in markup: " + ($gtBad -join '; ')) }

    Write-Output ''
    Write-Output ("DISCOVERY VERIFY: PASS={0} FAIL={1}" -f $pass, $fail)
    if ($fail -gt 0) { exit 1 }
}
finally { Pop-Location }
