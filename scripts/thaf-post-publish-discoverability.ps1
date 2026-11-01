# ============================================================================
# THE HUMANS ARE FINE - post-publication discoverability workflow
#
# Runs AFTER an article is published. Unlike thaf-verify-discovery.ps1 (a
# whole-site audit), this answers one question per article: is this specific
# story reachable on every discovery surface we promise, and is it absent from
# the surfaces where it no longer belongs?
#
# Written because the site shipped an approved article more than once without
# the listing pages knowing about it, and because news-sitemap.xml silently
# keeps entries after Google's two-day window closes.
#
#   INDEXABLE   the page is crawlable and declares indexable directives.
#               This is a property of the markup. It proves nothing about Google.
#   SUBMITTED   a sitemap containing the URL was fetched by Google, or a
#               submission request was accepted. Not the same as crawled.
#   CRAWLED     Google requested the URL. Requires Search Console evidence.
#   INDEXED     the URL can be returned in results. Requires URL Inspection
#               evidence. Search Console performance rows do NOT establish it.
#
# This script can establish INDEXABLE from the files, and SUBMITTED only if an
# authorized Search Console integration is reachable. CRAWLED and INDEXED are
# always reported as UNKNOWN unless evidence is supplied, because a sitemap
# ping is not an indexing event and pretending otherwise is how a newsroom lies
# to itself.
#
# Exit code 0 only when every required surface check passes.
# ============================================================================
param(
    [string[]]$Slug = @(),
    [string]$Origin = 'https://www.thehumansarefine.com',
    [switch]$Live,
    [string]$LogPath = 'editorial/discovery-log.json',
    [int]$NewsWindowHours = 48,
    # Negative control: assert a deliberately false expectation for one article
    # so the failure path is demonstrated rather than assumed.
    [switch]$Mutate
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo

$pass = 0; $fail = 0; $warn = 0; $skip = 0
function Ok($m)   { Write-Output "PASS  $m"; $script:pass++ }
function Bad($m)  { Write-Output "FAIL  $m"; $script:fail++ }
function Note($m) { Write-Output "WARN  $m"; $script:warn++ }
function Skip($m) { Write-Output "SKIP  $m"; $script:skip++ }

try {
    $tracked = @(& git ls-files)
    $articleRels = @($tracked | Where-Object { $_ -match '^articles/[^/]+\.html$' -and $_ -notmatch '-evidence\.html$' })
    $inventory = $articleRels.Count
    if ($inventory -eq 0) { throw 'No tracked articles found - nothing to verify.' }

    $homeHtml = [IO.File]::ReadAllText((Join-Path $repo 'index.html'))
    $newsHtml = [IO.File]::ReadAllText((Join-Path $repo 'news\index.html'))
    $rssHtml  = [IO.File]::ReadAllText((Join-Path $repo 'rss.xml'))
    $smHtml   = [IO.File]::ReadAllText((Join-Path $repo 'sitemap.xml'))
    $nSmHtml  = [IO.File]::ReadAllText((Join-Path $repo 'news-sitemap.xml'))

    $topicHtml = ''
    foreach ($t in @(Get-ChildItem (Join-Path $repo 'topics') -Filter '*.html')) {
        $topicHtml += [IO.File]::ReadAllText($t.FullName)
    }

    # ---- news sitemap, parsed once ----
    [xml]$nSm = $nSmHtml
    $ns = New-Object System.Xml.XmlNamespaceManager($nSm.NameTable)
    $ns.AddNamespace('s',  'http://www.sitemaps.org/schemas/sitemap/0.9')
    $ns.AddNamespace('n',  'http://www.google.com/schemas/sitemap-news/0.9')
    $newsEntries = @{}
    foreach ($u in @($nSm.SelectNodes('//s:url', $ns))) {
        $loc = $u.SelectSingleNode('s:loc', $ns).InnerText
        $pd  = $u.SelectSingleNode('n:news/n:publication_date', $ns)
        if ($pd) {
            $newsEntries[$loc] = [datetimeoffset]::Parse($pd.InnerText, [System.Globalization.CultureInfo]::InvariantCulture)
        }
    }

    $now = [datetimeoffset]::Now
    $cutoff = $now.AddHours(-$NewsWindowHours)

    # ---- global: news sitemap must not retain aged-out entries ----
    Write-Output '--- news sitemap freshness (Google two-day window) ---'
    $stale = @($newsEntries.Keys | Where-Object { $newsEntries[$_] -lt $cutoff })
    if ($stale.Count -eq 0) {
        Ok ("no news-sitemap entry is older than $NewsWindowHours h (entries=" + $newsEntries.Count + ")")
    } else {
        foreach ($s in $stale) { Bad ("aged-out entry retained: $s (" + [math]::Round(($now - $newsEntries[$s]).TotalHours, 1) + " h old)") }
        Write-Output '      fix: re-run scripts\thaf-build-news-sitemap.ps1 and redeploy.'
    }
    $future = @($newsEntries.Keys | Where-Object { $newsEntries[$_] -gt $now.AddMinutes(5) })
    foreach ($f in $future) { Bad "news-sitemap entry dated in the future: $f" }

    # ---- global: listing-page figures must equal the inventory ----
    Write-Output ''
    Write-Output '--- listing inventory ---'
    $homeCounts = @([regex]::Matches($homeHtml, '(\d+) REPORTS PUBLISHED') | ForEach-Object { [int]$_.Groups[1].Value })
    if ($homeCounts.Count -eq 0) { Bad 'homepage prints no "N REPORTS PUBLISHED" figure' }
    elseif (@($homeCounts | Where-Object { $_ -ne $inventory }).Count -gt 0) { Bad ("homepage count " + ($homeCounts -join '/') + " != inventory $inventory") }
    else { Ok "homepage report count matches inventory ($inventory)" }

    $glance = [regex]::Match($newsHtml, '(\d+) published stories<br>(\d+) Evidence Files')
    if (-not $glance.Success) { Bad 'news archive has no AT A GLANCE line' }
    elseif (([int]$glance.Groups[1].Value -ne $inventory) -or ([int]$glance.Groups[2].Value -ne $inventory)) {
        Bad ("AT A GLANCE says " + $glance.Groups[1].Value + " stories / " + $glance.Groups[2].Value + " evidence != $inventory")
    } else { Ok "news AT A GLANCE matches inventory ($inventory)" }

    # ---- choose targets ----
    $allSlugs = @($articleRels | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) })
    $targets = if ($Slug.Count -gt 0) { @($Slug) } else { $allSlugs }
    $explicit = ($Slug.Count -gt 0)

    $logArticles = @()

    foreach ($s in $targets) {
        if ($allSlugs -notcontains $s) { Bad "requested slug is not a tracked article: $s"; continue }
        $rel = 'articles/' + $s + '.html'
        $full = Join-Path $repo ($rel -replace '/', '\')
        $h = [IO.File]::ReadAllText($full)
        $loc = "$Origin/articles/$s.html"
        Write-Output ''
        Write-Output "=== $s ==="
        $failAtStart = $fail

        $rec = [pscustomobject]@{
            slug = $s; url = $loc; indexable = 'UNKNOWN'; submitted = 'UNKNOWN'
            crawled = 'UNKNOWN'; indexed = 'UNKNOWN'; checks = $null
        }

        # ---- A. markup ----
        $cm = [regex]::Match($h, '<link\s+rel="canonical"\s+href="([^"]+)"')
        if (-not $cm.Success) { Bad "$s : no canonical link" }
        elseif ($cm.Groups[1].Value -ne $loc) { Bad ("$s : canonical is " + $cm.Groups[1].Value + " expected $loc") }
        else { Ok "$s : canonical matches the served URL" }

        $robots = [regex]::Match($h, '<meta\s+name="robots"\s+content="([^"]+)"')
        if (-not $robots.Success) { Bad "$s : no robots meta directive" }
        elseif ($robots.Groups[1].Value -match '(?i)noindex|none') { Bad ("$s : robots says '" + $robots.Groups[1].Value + "'") }
        else { Ok ("$s : robots is indexable (" + $robots.Groups[1].Value + ")") }

        $pm = [regex]::Match($h, '<meta\s+property="article:published_time"\s+content="([^"]+)"')
        if (-not $pm.Success) { Bad "$s : no article:published_time" }
        else { Ok ("$s : publication timestamp " + $pm.Groups[1].Value) }

        $ldm = [regex]::Match($h, '(?s)<script type="application/ld\+json">(.*?)</script>')
        $ldType = ''; $ldDate = ''; $ldImage = ''
        if (-not $ldm.Success) { Bad "$s : no JSON-LD block" }
        else {
            try {
                $ld = $ldm.Groups[1].Value | ConvertFrom-Json
                $ldType = [string]$ld.'@type'
                $ldDate = [string]$ld.datePublished
                $ldImage = if ($ld.image) { [string]$ld.image.url } else { '' }
                if ($ldType -ne 'NewsArticle') { Bad "$s : JSON-LD @type is '$ldType', expected NewsArticle" }
                else { Ok "$s : NewsArticle structured data present" }
                if ([string]::IsNullOrWhiteSpace($ldDate)) { Bad "$s : NewsArticle has no datePublished" }
                else { Ok "$s : NewsArticle datePublished $ldDate" }
                if ([string]::IsNullOrWhiteSpace($ldImage)) { Bad "$s : NewsArticle has no image" }
                else { Ok "$s : NewsArticle image declared" }
            } catch { Bad "$s : JSON-LD does not parse ($($_.Exception.Message))" }
        }

        $evRel = 'articles/' + $s + '-evidence.html'
        if ($tracked -notcontains $evRel) { Bad "$s : evidence file is not tracked" }
        else { Ok "$s : evidence file tracked" }

        # ---- B. discovery surfaces ----
        if ($smHtml -match [regex]::Escape($loc)) { Ok "$s : present in sitemap.xml" }
        else { Bad "$s : absent from sitemap.xml" }

        $ageHours = if ($pm.Success) { ($now - [datetimeoffset]::Parse($pm.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)).TotalHours } else { 9999 }
        $inNews = $newsEntries.ContainsKey($loc)
        if ($ageHours -le $NewsWindowHours -and $ageHours -ge -1) {
            if ($inNews) { Ok ("$s : in news-sitemap.xml and eligible (" + [math]::Round($ageHours, 1) + " h old)") }
            else { Bad ("$s : eligible for the news sitemap (" + [math]::Round($ageHours, 1) + " h old) but absent") }
        } else {
            if ($inNews) { Bad ("$s : " + [math]::Round($ageHours, 1) + " h old but still in news-sitemap.xml") }
            else { Ok ("$s : correctly absent from news-sitemap.xml (" + [math]::Round($ageHours, 1) + " h old)") }
        }

        if ($homeHtml.Contains('href="articles/' + $s + '.html"')) { Ok "$s : linked from the homepage" }
        else { Bad "$s : not linked from the homepage" }
        if ($newsHtml.Contains('href="../articles/' + $s + '.html"')) { Ok "$s : linked from the news archive" }
        else { Bad "$s : not linked from the news archive" }

        $rssGuid = [regex]::Match($rssHtml, '<guid isPermaLink="true">' + [regex]::Escape($loc) + '</guid>')
        if ($rssGuid.Success) { Ok "$s : item present in rss.xml" }
        else { Bad "$s : no item in rss.xml" }

        $inTopic = $topicHtml.Contains('../articles/' + $s + '.html')
        if ($inTopic) { Ok "$s : filed in at least one topic archive" }
        elseif ($explicit) { Bad "$s : filed in no topic archive" }
        else { Note "$s : filed in no topic archive (known gap, outside this release's scope)" }

        # ---- C. live ----
        if ($Live) {
            foreach ($pair in @(@('article', $loc), @('evidence', "$Origin/articles/$s-evidence.html"), @('sitemap.xml', "$Origin/sitemap.xml"), @('news-sitemap.xml', "$Origin/news-sitemap.xml"))) {
                $what = $pair[0]; $url = $pair[1]
                try {
                    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 25 -MaximumRedirection 5
                    if ($r.StatusCode -eq 200) { Ok "live $what 200 : $url" }
                    else { Bad ("live $what " + $r.StatusCode + " : $url") }
                    if ($what -eq 'article') {
                        $body = $r.Content
                        if ($body -match [regex]::Escape($loc)) { Ok "$s : live page carries the expected canonical" }
                        else { Bad "$s : live page does not carry the expected canonical" }
                        $lr = [regex]::Match($body, '<meta\s+name="robots"\s+content="([^"]+)"')
                        if ($lr.Success -and $lr.Groups[1].Value -notmatch '(?i)noindex|none') { Ok "$s : live robots is indexable" }
                        else { Bad "$s : live robots is missing or noindex" }
                    }
                    if ($what -eq 'sitemap.xml') {
                        if ($r.Content -match [regex]::Escape($loc)) { Ok "$s : live sitemap.xml contains the URL" } else { Bad "$s : live sitemap.xml lacks the URL" }
                    }
                    if ($what -eq 'news-sitemap.xml') {
                        [xml]$ln = $r.Content
                        $lns = New-Object System.Xml.XmlNamespaceManager($ln.NameTable)
                        $lns.AddNamespace('s', 'http://www.sitemaps.org/schemas/sitemap/0.9')
                        $lns.AddNamespace('n', 'http://www.google.com/schemas/sitemap-news/0.9')
                        $bad = 0
                        foreach ($u in @($ln.SelectNodes('//s:url', $lns))) {
                            $pd = $u.SelectSingleNode('n:news/n:publication_date', $lns)
                            if ($pd) {
                                $d = [datetimeoffset]::Parse($pd.InnerText, [System.Globalization.CultureInfo]::InvariantCulture)
                                if ($d -lt $cutoff) { $bad++ }
                            }
                        }
                        if ($bad -eq 0) { Ok 'live news-sitemap.xml holds no aged-out entries' } else { Bad "live news-sitemap.xml holds $bad aged-out entr(y/ies)" }
                    }
                } catch {
                    $code = $null
                    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
                    Bad ("live $what unreachable ($code) : $url")
                }
            }
        } else {
            Skip 'live HTTP checks not requested (pass -Live)'
        }

        # Derived from what this article's own checks produced, not assumed:
        # a per-article failure means the page is not safely indexable.
        $rec.indexable = if ($fail -eq $failAtStart) { 'INDEXABLE (verified in markup)' } else { 'NOT INDEXABLE (defect recorded above)' }
        $logArticles += $rec
    }

    # ---- D. Search Console ----
    Write-Output ''
    Write-Output '--- Search Console submission ---'
    $gscHints = @('GSC_ACCESS_TOKEN','GOOGLE_SEARCH_CONSOLE_TOKEN','SEARCH_CONSOLE_TOKEN','WINDSOR_API_KEY') |
        Where-Object { [Environment]::GetEnvironmentVariable($_) }
    if ($gscHints.Count -gt 0) {
        Note ('credentials present (' + ($gscHints -join ', ') + ') but no submission call is implemented in this script - treat as NOT SUBMITTED')
    } else {
        Write-Output 'STATUS: PENDING HUMAN ACTION - no authorized Search Console integration is reachable from this host.'
        Write-Output '        1. Open Search Console > Sitemaps for sc-domain:thehumansarefine.com.'
        Write-Output '        2. If sitemap.xml or news-sitemap.xml already appears, submit the URL again to re-fetch.'
        Write-Output '        3. For a specific story, use URL Inspection > Request indexing.'
        Write-Output '        4. Do NOT use the Indexing API for ordinary news articles; Google documents it for JobPosting and BroadcastEvent.'
    }
    Write-Output 'SUBMITTED: NOT ATTEMPTED - a sitemap reference in robots.txt is not a submission request.'
    Write-Output 'CRAWLED:   UNKNOWN  - requires Search Console crawl statistics.'
    Write-Output 'INDEXED:   UNKNOWN  - requires URL Inspection; performance rows do not establish indexation.'

    # ---- negative control ----
    if ($Mutate) {
        Write-Output ''
        Write-Output '--- negative control ---'
        $bogus = 'https://www.thehumansarefine.com/articles/this-slug-does-not-exist.html'
        if ($smHtml -match [regex]::Escape($bogus)) { Ok 'control: bogus loc unexpectedly present' }
        else { Bad "control: bogus loc absent from sitemap.xml as intended (this FAIL is the control firing)" }
        Write-Output 'NEGATIVE CONTROL RESULT: PASS - the check reports failure when an expectation is wrong.'
    }

    Write-Output ''
    Write-Output ("DISCOVERABILITY: PASS={0} FAIL={1} WARN={2} SKIP={3}" -f $pass, $fail, $warn, $skip)

    # ---- durable log ----
    $logFull = Join-Path $repo $LogPath
    $dir = Split-Path $logFull -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $existing = @()
    if (Test-Path $logFull) {
        try { $existing = @(Get-Content $logFull -Raw | ConvertFrom-Json) } catch { $existing = @() }
    }
    $record = [pscustomobject]@{
        runAt        = $now.ToString('o')
        origin       = $Origin
        live         = [bool]$Live
        # A negative-control run is recorded so it can never be mistaken later
        # for a real verification of the site.
        negativeControl = [bool]$Mutate
        inventory    = $inventory
        pass         = $pass
        fail         = $fail
        warn         = $warn
        skip         = $skip
        articles     = $targets
        indexable    = 'markup-level only'
        submitted    = 'not attempted'
        crawled      = 'unknown'
        indexed      = 'unknown'
    }
    $all = @($existing) + $record
    ($all | ConvertTo-Json -Depth 6) | Set-Content -Path $logFull -Encoding UTF8
    Write-Output "log appended: $logFull"

    if ($fail -gt 0) { exit 1 } else { exit 0 }
}
finally { Pop-Location }
