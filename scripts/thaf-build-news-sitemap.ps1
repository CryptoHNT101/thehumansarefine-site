# ============================================================================
# THE HUMANS ARE FINE - build news-sitemap.xml
#
# A separate news sitemap, per Google's "News sitemaps" documentation
# (https://developers.google.com/search/docs/crawling-indexing/sitemaps/news-sitemap,
# page last updated 2025-12-10 UTC):
#
#   - required tags: news:news, news:publication (news:name + news:language),
#     news:publication_date, news:title
#   - namespace: http://www.google.com/schemas/sitemap-news/0.9
#   - "Only include recent URLs for articles that were created in the last two
#     days." Older articles are dropped, not back-dated.
#   - "Specify the original date and time when the article was first published
#     on your site. Don't specify the time when you added the article to your
#     sitemap." => the date comes from article:published_time in the HTML, not
#     from the build clock and not from git.
#   - up to 1,000 news:news tags per sitemap; split if more.
#   - an empty news sitemap is explicitly acceptable to Google.
#
# Evidence File pages are EXCLUDED. They are records, not article URLs, and
# news:title would have to misrepresent them to include them.
#
# This script refuses to invent a date: an article with no publication time is
# a hard failure, not a silent omission.
# ============================================================================
param(
    [string]$Out = 'news-sitemap.xml',
    [int]$WindowHours = 48,
    [string]$Origin = 'https://www.thehumansarefine.com',
    [string]$PublicationName = 'THE HUMANS ARE FINE',
    [string]$Language = 'en',
    # Fixed clock for reproducible tests. Omit in production.
    [Nullable[datetimeoffset]]$Now = $null
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    if ($null -eq $Now) { $Now = [datetimeoffset]::Now }
    $cutoff = $Now.AddHours(-$WindowHours)

    $tracked = @(git ls-files) | ForEach-Object { $_.Trim() }
    $articleFiles = @($tracked | Where-Object { $_ -like 'articles/*.html' -and $_ -notlike '*-evidence.html' })
    if ($articleFiles.Count -eq 0) { throw 'No article pages found under articles/ - refusing to write an empty sitemap that looks like a decision.' }

    $entries = @()
    foreach ($rel in $articleFiles) {
        $full = Join-Path $repo $rel
        if (-not (Test-Path $full)) { throw "Tracked article missing from disk: $rel" }
        $html = [System.IO.File]::ReadAllText($full)

        $pm = [regex]::Match($html, '<meta\s+property="article:published_time"\s+content="([^"]+)"')
        if (-not $pm.Success) { throw "$rel has no article:published_time - cannot state a publication date honestly." }
        $published = [datetimeoffset]::Parse($pm.Groups[1].Value.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)

        $tm = [regex]::Match($html, '(?is)<title>(.*?)</title>')
        if (-not $tm.Success) { throw "$rel has no <title> - news:title is required." }
        $title = [System.Net.WebUtility]::HtmlDecode($tm.Groups[1].Value.Trim())

        $cm = [regex]::Match($html, '<link\s+rel="canonical"\s+href="([^"]+)"')
        if (-not $cm.Success) { throw "$rel has no canonical URL." }
        $loc = $cm.Groups[1].Value.Trim()
        if (-not $loc.StartsWith($Origin)) { throw "$rel canonical does not point at $Origin : $loc" }

        # Published in the last two days => belongs in the news sitemap.
        if ($published -gt $Now) {
            # A future publication date is a data error, not a fresh article.
            throw ("$rel is dated in the future ({0:O}); refusing to publish a sitemap claiming content is not yet published." -f $published)
        }
        if ($published -lt $cutoff) { continue }

        $entries += [pscustomobject]@{
            loc       = $loc
            title     = $title
            published = $published
            rel       = $rel
        }
    }

    $entries = @($entries | Sort-Object published -Descending)
    if ($entries.Count -gt 1000) { throw ("{0} recent articles exceeds Google's 1,000-per-sitemap limit; split into multiple news sitemaps." -f $entries.Count) }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sb.AppendLine('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"')
    [void]$sb.AppendLine('        xmlns:news="http://www.google.com/schemas/sitemap-news/0.9">')
    foreach ($e in $entries) {
        $date = $e.published.ToString('yyyy-MM-ddTHH:mm:sszzz')
        $escTitle = [System.Security.SecurityElement]::Escape($e.title)
        $escLoc = [System.Security.SecurityElement]::Escape($e.loc)
        $escName = [System.Security.SecurityElement]::Escape($PublicationName)
        [void]$sb.AppendLine('  <url>')
        [void]$sb.AppendLine("    <loc>$escLoc</loc>")
        [void]$sb.AppendLine('    <news:news>')
        [void]$sb.AppendLine('      <news:publication>')
        [void]$sb.AppendLine("        <news:name>$escName</news:name>")
        [void]$sb.AppendLine("        <news:language>$Language</news:language>")
        [void]$sb.AppendLine('      </news:publication>')
        [void]$sb.AppendLine("      <news:publication_date>$date</news:publication_date>")
        [void]$sb.AppendLine("      <news:title>$escTitle</news:title>")
        [void]$sb.AppendLine('    </news:news>')
        [void]$sb.AppendLine('  </url>')
    }
    [void]$sb.AppendLine('</urlset>')

    $target = Join-Path $repo $Out
    [IO.File]::WriteAllText($target, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

    # ---- validate what was just written ----
    [xml]$check = Get-Content $target -Raw -Encoding UTF8
    $ns = New-Object System.Xml.XmlNamespaceManager($check.NameTable)
    $ns.AddNamespace('s', 'http://www.sitemaps.org/schemas/sitemap/0.9')
    $ns.AddNamespace('n', 'http://www.google.com/schemas/sitemap-news/0.9')
    $urls = @($check.SelectNodes('//s:url', $ns))
    foreach ($u in $urls) {
        $loc = $u.SelectSingleNode('s:loc', $ns).InnerText
        $news = $u.SelectSingleNode('n:news', $ns)
        if (-not $news) { throw "news:news missing for $loc" }
        $name = $u.SelectSingleNode('n:news/n:publication/n:name', $ns)
        $lang = $u.SelectSingleNode('n:news/n:publication/n:language', $ns)
        $pd = $u.SelectSingleNode('n:news/n:publication_date', $ns)
        $ti = $u.SelectSingleNode('n:news/n:title', $ns)
        foreach ($pair in @(@('news:name', $name), @('news:language', $lang), @('news:publication_date', $pd), @('news:title', $ti))) {
            if (-not $pair[1] -or [string]::IsNullOrWhiteSpace($pair[1].InnerText)) { throw ("{0} is empty for {1}" -f $pair[0], $loc) }
        }
        if ($loc -like '*-evidence.html') { throw "Evidence File page in news sitemap: $loc" }
        $parsedDate = [datetimeoffset]::Parse($pd.InnerText, [System.Globalization.CultureInfo]::InvariantCulture)
        if ($parsedDate -lt $cutoff) { throw "$loc is older than the $WindowHours hour window but was included" }
        if ($parsedDate -gt $Now) { throw "$loc has a future publication date" }
    }
    $dupLocs = @($urls | ForEach-Object { $_.SelectSingleNode('s:loc', $ns).InnerText } | Group-Object | Where-Object { $_.Count -gt 1 })
    if ($dupLocs.Count -gt 0) { throw ('duplicate loc entries: ' + (($dupLocs | ForEach-Object { $_.Name }) -join ', ')) }

    Write-Output ("news sitemap written: {0} URLs within a {1}h window ending {2:yyyy-MM-ddTHH:mm:sszzz}" -f $urls.Count, $WindowHours, $Now)
    if ($urls.Count -eq 0) { Write-Output 'note: empty news sitemap - Google documents this as acceptable, not an error.' }
    foreach ($u in $urls) {
        Write-Output ("  {0}  {1}" -f $u.SelectSingleNode('n:news/n:publication_date', $ns).InnerText, $u.SelectSingleNode('s:loc', $ns).InnerText)
    }
}
finally { Pop-Location }
