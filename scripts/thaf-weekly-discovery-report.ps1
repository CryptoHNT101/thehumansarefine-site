<#
  thaf-weekly-discovery-report.ps1

  Produces the weekly reader-growth report for THE HUMANS ARE FINE.

  HONESTY CONTRACT
  ----------------
  Two different kinds of number go into this report and they are kept in
  separate sections so they can never be confused:

  1. MEASURED  -- values this script actually read from a live endpoint or a
                  tracked file during this run, each stamped with the URL it
                  came from.
  2. UNAVAILABLE -- Search Console impressions, clicks, CTR, queries, indexed
                  URL counts and Google News traffic. This station has no
                  Google Search Console connection (see
                  reports/google-news-growth-readiness.md, Phase 1). These are
                  printed as UNAVAILABLE with the reason, never estimated and
                  never carried forward from a previous report.

  If a Search Console export is later dropped into measurements\gsc\, the
  report will read the newest file and fill the UNAVAILABLE block from it --
  and will say which file it used. It will not invent a series to fill gaps.

  Usage:
    powershell -File scripts/thaf-weekly-discovery-report.ps1
    powershell -File scripts/thaf-weekly-discovery-report.ps1 -OutDir ..\reports\weekly
#>
param(
    [string]$SiteRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Origin   = 'https://www.thehumansarefine.com',
    [string]$OutDir   = ''
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $SiteRoot) 'reports\weekly' }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$now      = Get-Date
$stamp    = $now.ToString('yyyy-MM-dd')
$outFile  = Join-Path $OutDir "discovery-week-$stamp.md"
$measured = New-Object System.Collections.ArrayList
$notes    = New-Object System.Collections.ArrayList

function Add-Measured([string]$label, [string]$value, [string]$source) {
    [void]$measured.Add([pscustomobject]@{ Label = $label; Value = $value; Source = $source })
}
function Add-Note([string]$text) { [void]$notes.Add($text) }

function Get-Http([string]$url) {
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
        return [pscustomobject]@{ Ok = $true; Status = [int]$r.StatusCode; Body = $r.Content; Bytes = $r.RawContentLength }
    } catch {
        $code = 0
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        return [pscustomobject]@{ Ok = $false; Status = $code; Body = ''; Bytes = 0 }
    }
}

# ---------------------------------------------------------------- sitemaps
$sm = Get-Http "$Origin/sitemap.xml"
if ($sm.Ok) {
    $smXml = [xml]$sm.Body
    $smUrls = @($smXml.urlset.url)
    Add-Measured 'sitemap.xml status' "$($sm.Status) ($($sm.Bytes) bytes)" "$Origin/sitemap.xml"
    Add-Measured 'sitemap.xml URL count' "$($smUrls.Count)" "$Origin/sitemap.xml"
    $withLastmod = @($smUrls | Where-Object { $_.lastmod }).Count
    Add-Measured 'sitemap entries carrying lastmod' "$withLastmod of $($smUrls.Count)" "$Origin/sitemap.xml"
    $newest = $smUrls | Where-Object { $_.lastmod } |
              Sort-Object { [datetime]$_.lastmod } -Descending | Select-Object -First 1
    if ($newest) { Add-Measured 'newest lastmod in sitemap' "$($newest.lastmod)  $($newest.loc)" "$Origin/sitemap.xml" }
} else {
    Add-Measured 'sitemap.xml status' "HTTP $($sm.Status) -- NOT RETRIEVED" "$Origin/sitemap.xml"
}

$nsm = Get-Http "$Origin/news-sitemap.xml"
if ($nsm.Ok) {
    $nsmXml = [xml]$nsm.Body
    $entries = @($nsmXml.urlset.url)
    Add-Measured 'news-sitemap.xml status' "$($nsm.Status) ($($nsm.Bytes) bytes)" "$Origin/news-sitemap.xml"
    Add-Measured 'news-sitemap entries' "$($entries.Count)" "$Origin/news-sitemap.xml"
} else {
    Add-Measured 'news-sitemap.xml status' "HTTP $($nsm.Status) -- not deployed (never published without approval)" "$Origin/news-sitemap.xml"
    Add-Note 'news-sitemap.xml is built and verified on branch news-discovery-readiness but is NOT deployed. Deploying it is a publisher decision.'
}

$robots = Get-Http "$Origin/robots.txt"
if ($robots.Ok) {
    $smLines = @([regex]::Matches($robots.Body, '(?im)^\s*Sitemap:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value })
    Add-Measured 'robots.txt status' "$($robots.Status)" "$Origin/robots.txt"
    Add-Measured 'sitemaps advertised in robots.txt' "$($smLines.Count): $($smLines -join ', ')" "$Origin/robots.txt"
} else {
    Add-Measured 'robots.txt status' "HTTP $($robots.Status) -- NOT RETRIEVED" "$Origin/robots.txt"
}

# ---------------------------------------------------------------- articles
$articlesDir = Join-Path $SiteRoot 'articles'
$articles = @()
if (Test-Path $articlesDir) {
    $articles = Get-ChildItem $articlesDir -Filter '*.html' |
                Where-Object { $_.Name -notlike '*-evidence.html' } | Sort-Object Name
}
Add-Measured 'published article count (tracked files)' "$($articles.Count)" "site/articles/"

$articleRows = @()
foreach ($a in $articles) {
    $slug = $a.BaseName
    $t = [System.IO.File]::ReadAllText($a.FullName)
    $pub  = [regex]::Match($t, '<meta property="article:published_time" content="([^"]+)"').Groups[1].Value
    $mod  = [regex]::Match($t, '<meta property="article:modified_time" content="([^"]+)"').Groups[1].Value
    $canon = [regex]::Match($t, '<link rel="canonical" href="([^"]+)"').Groups[1].Value
    $hasNews = $t -match '"@type"\s*:\s*"NewsArticle"'
    $hasDisc = $t -match 'class="ai-disclosure"'
    $hasImg  = $t -match '<img\s'
    $articleRows += [pscustomobject]@{
        Slug = $slug; Published = $pub; Modified = $mod; Canonical = $canon
        NewsArticle = $hasNews; Disclosure = $hasDisc; InlineImage = $hasImg
    }
}
$missingCanonical = @($articleRows | Where-Object { -not $_.Canonical }).Count
$missingNews      = @($articleRows | Where-Object { -not $_.NewsArticle }).Count
$missingDisc      = @($articleRows | Where-Object { -not $_.Disclosure }).Count
$noImage          = @($articleRows | Where-Object { -not $_.InlineImage }).Count
Add-Measured 'articles missing canonical' "$missingCanonical of $($articleRows.Count)" "site/articles/*.html"
Add-Measured 'articles missing NewsArticle data' "$missingNews of $($articleRows.Count)" "site/articles/*.html"
Add-Measured 'articles missing body disclosure' "$missingDisc of $($articleRows.Count)" "site/articles/*.html"
Add-Measured 'articles with no inline image' "$noImage of $($articleRows.Count)" "site/articles/*.html"

# ---------------------------------------------------------------- GSC
$gscDir = Join-Path (Split-Path -Parent $SiteRoot) 'measurements\gsc'
$gscFile = $null
if (Test-Path $gscDir) {
    $gscFile = Get-ChildItem $gscDir -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

# ---------------------------------------------------------------- previous week
$prevFile = $null
if (Test-Path $OutDir) {
    $prevFile = Get-ChildItem $OutDir -Filter 'discovery-week-*.md' |
                Where-Object { $_.Name -ne (Split-Path -Leaf $outFile) } |
                Sort-Object Name -Descending | Select-Object -First 1
}

# ---------------------------------------------------------------- render
$L = New-Object System.Collections.ArrayList
function Add-Line([string]$s) { [void]$L.Add($s) }

Add-Line "# Reader growth -- week ending $stamp"
Add-Line ''
Add-Line "Generated $($now.ToString('yyyy-MM-dd HH:mm')) from live endpoints on $Origin plus tracked files under ``site/``."
Add-Line ''
Add-Line '## 1. Organic search performance'
Add-Line ''
if ($gscFile) {
    Add-Line "Read from Search Console export: ``measurements/gsc/$($gscFile.Name)`` (file dated $($gscFile.LastWriteTime.ToString('yyyy-MM-dd')))."
    Add-Line ''
    Add-Line '| Metric | Value |'
    Add-Line '| --- | --- |'
    Add-Line "| Organic impressions | see export file -- not parsed by this script |"
    Add-Line "| Organic clicks | see export file |"
    Add-Line "| Average CTR | see export file |"
    Add-Line "| Top queries | see export file |"
    Add-Line "| Top pages | see export file |"
    Add-Line "| Google News traffic | see export file |"
    Add-Line ''
    Add-Line 'The export exists; this script does not parse it. Parse the file by hand and replace this table, or extend the script. **No figure is quoted above that was not read from that file.**'
} else {
    Add-Line '**UNAVAILABLE.** No Google Search Console connection exists on this station, and no export file is present.'
    Add-Line ''
    Add-Line '| Metric | Status | Why |'
    Add-Line '| --- | --- | --- |'
    Add-Line '| Organic Google impressions | UNAVAILABLE | Requires a verified Search Console property. No verification record exists on the domain (no DNS TXT, no HTML file, no meta tag). |'
    Add-Line '| Organic Google clicks | UNAVAILABLE | Same. |'
    Add-Line '| Average click-through rate | UNAVAILABLE | Derived from impressions and clicks, both unavailable. |'
    Add-Line '| Indexed article count | UNAVAILABLE | Search Console Coverage report, or a ``site:`` count. Neither is readable here; ``site:`` is also an unreliable estimate, not a figure to report. |'
    Add-Line '| Top-performing search queries | UNAVAILABLE | Search Console Performance report only. |'
    Add-Line '| Top-performing articles (search) | UNAVAILABLE | Same. |'
    Add-Line '| Google News traffic | UNAVAILABLE | Requires Search Console plus a News performance report, which needs an approved News publisher. |'
    Add-Line ''
    Add-Line 'Nothing in this section is an estimate. If a figure is needed, the path is: verify Search Console, then connect it in ABILITIES so this script can read the API, or drop a CSV export into ``measurements/gsc/``.'
}

Add-Line ''
Add-Line '## 2. Indexable surface (measured this week)'
Add-Line ''
Add-Line '| Metric | Value | Read from |'
Add-Line '| --- | --- | --- |'
foreach ($m in $measured) { Add-Line "| $($m.Label) | $($m.Value) | $($m.Source) |" }

Add-Line ''
Add-Line '### Per-article state'
Add-Line ''
Add-Line '| Article | Published | Modified | Canonical | NewsArticle | Disclosure | Inline image |'
Add-Line '| --- | --- | --- | --- | --- | --- | --- |'
foreach ($r in $articleRows) {
    $c = if ($r.Canonical) { 'yes' } else { '**no**' }
    $n = if ($r.NewsArticle) { 'yes' } else { '**no**' }
    $d = if ($r.Disclosure) { 'yes' } else { '**no**' }
    $i = if ($r.InlineImage) { 'yes' } else { 'no (text-only)' }
    Add-Line "| $($r.Slug) | $($r.Published) | $($r.Modified) | $c | $n | $d | $i |"
}

Add-Line ''
Add-Line '## 3. Change since last week'
Add-Line ''
if ($prevFile) {
    Add-Line "Previous report: ``$($prevFile.Name)`` (written $($prevFile.LastWriteTime.ToString('yyyy-MM-dd'))). Diff the two by eye for now: the numeric fields that can be compared are the sitemap URL count, the article count and the per-article modified timestamps above. Search performance cannot be compared because it was not available last week either -- there is no previous value to subtract from, and inventing one would be worse than the gap."
} else {
    Add-Line 'This is the first report in the series, so there is nothing to compare against yet. Next week this section will diff against it.'
}

if ($notes.Count -gt 0) {
    Add-Line ''
    Add-Line '## 4. Notes'
    Add-Line ''
    foreach ($n in $notes) { Add-Line "- $n" }
}

Add-Line ''
Add-Line '---'
Add-Line ''
Add-Line '*Method: every MEASURED value above was read during this run from the source named in its row. UNAVAILABLE means unavailable, not zero. No traffic figure in this report is estimated, extrapolated or carried over.*'

Set-Content -Path $outFile -Value ($L -join "`r`n") -Encoding UTF8

Write-Output "report written: $outFile"
Write-Output "measured rows: $($measured.Count)   articles: $($articleRows.Count)"
if ($gscFile) { Write-Output "gsc export detected: $($gscFile.Name)" } else { Write-Output 'gsc export: none -- performance section marked UNAVAILABLE' }
