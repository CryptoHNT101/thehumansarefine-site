# ============================================================================
# THE HUMANS ARE FINE - keep rss.xml in step with the published stories
#
# The feed is the one channel a reader can subscribe to directly, and nothing
# was keeping it true. It currently carries five headlines that no longer match
# the page they point at (titles were shortened when the site was built, then
# the pages were rewritten), no item for the two newest stories, and a
# lastBuildDate that only moved when somebody remembered.
#
# What this script does, and does not do:
#   * <title> is copied from the article's own <title>. It cannot drift again.
#   * <pubDate> is copied from scripts/page-dates.json, which is derived from
#     git history. A story with no date is an error, not a guess.
#   * An item's existing <description> is preserved - those sentences are the
#     feed's own editorial summaries and are not regenerated here. A story that
#     has no item yet gets its page meta description.
#   * Items are ordered newest first and lastBuildDate is the newest pubDate.
#   * Every <link> must resolve to a tracked file, and the item count must
#     equal the number of tracked stories, or the script fails.
# ============================================================================
param([string]$Feed = 'rss.xml', [string]$DatesFile = 'scripts/page-dates.json', [switch]$WhatIf)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    $origin = 'https://www.thehumansarefine.com'
    $tracked = @(git ls-files) | ForEach-Object { $_.Trim() }
    if (-not (Test-Path $DatesFile)) { throw "Missing $DatesFile. Run scripts/thaf-page-dates.ps1 first." }
    $dates = @{}
    foreach ($r in (Get-Content $DatesFile -Raw -Encoding UTF8 | ConvertFrom-Json)) { $dates[$r.path] = $r }

    function Decode([string]$s) {
        if ($null -eq $s) { return '' }
        $s = $s -replace '&mdash;', [char]0x2014
        $s = $s -replace '&amp;', '&'
        $s = $s -replace '&quot;', '"'
        $s = $s -replace '&#39;', "'"
        $s = $s -replace '&apos;', "'"
        $s = $s -replace '&rsquo;', [char]0x2019
        $s = $s -replace '&ldquo;', [char]0x201C
        $s = $s -replace '&rdquo;', [char]0x201D
        return $s.Trim()
    }
    function Esc([string]$s) { return [System.Security.SecurityElement]::Escape($s) }

    $rel = Join-Path $repo $Feed
    $raw = [IO.File]::ReadAllText($rel)

    # ---- read what the feed has now ---------------------------------------
    $existing = @{}
    foreach ($m in [regex]::Matches($raw, '(?s)<item>(.*?)</item>')) {
        $block = $m.Groups[1].Value
        $link = ([regex]::Match($block, '<link>(.*?)</link>')).Groups[1].Value.Trim()
        $existing[$link] = [pscustomobject]@{
            Link = $link
            Description = ([regex]::Match($block, '(?s)<description>(.*?)</description>')).Groups[1].Value.Trim()
        }
    }

    # ---- every tracked story gets exactly one item -------------------------
    $stories = @($tracked | Where-Object { $_ -like 'articles/*.html' -and $_ -notlike '*-evidence.html' } | Sort-Object)
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($s in $stories) {
        if (-not $dates.ContainsKey($s)) { throw "No git date for $s - cannot honestly set pubDate." }
        $page = [IO.File]::ReadAllText((Join-Path $repo $s))
        $title = Decode ([regex]::Match($page, '(?is)<title>(.*?)</title>')).Groups[1].Value
        $url = "$origin/$s"
        $desc = $null
        if ($existing.ContainsKey($url) -and $existing[$url].Description) { $desc = $existing[$url].Description }
        else {
            $md = [regex]::Match($page, '(?is)<meta\s+name="description"\s+content="(.*?)"')
            if (-not $md.Success) { throw "$s has no meta description to seed the feed with." }
            $desc = Esc (Decode $md.Groups[1].Value)
        }
        $category = Decode ([regex]::Match($page, '(?is)<li><b>Category</b>\s*(.*?)</li>')).Groups[1].Value
        if (-not $category) { $category = 'News' }
        $when = [datetime]$dates[$s].published
        $items.Add([pscustomobject]@{
                Title = $title; Link = $url; Description = $desc
                Category = $category; When = $when
                Pub = $when.ToUniversalTime().ToString('ddd, dd MMM yyyy HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture) + ' GMT'
            })
    }

    $items = @($items | Sort-Object When -Descending)
    $newest = $items[0].When.ToUniversalTime().ToString('ddd, dd MMM yyyy HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture) + ' GMT'

    # ---- rewrite -----------------------------------------------------------
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sb.AppendLine('<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">')
    [void]$sb.AppendLine('<channel>')
    [void]$sb.AppendLine('<title>THE HUMANS ARE FINE.</title>')
    [void]$sb.AppendLine("<link>$origin/</link>")
    [void]$sb.AppendLine("<atom:link href=`"$origin/rss.xml`" rel=`"self`" type=`"application/rss+xml`" />")
    [void]$sb.AppendLine('<description>Independent AI journalism. Every story carries a public Evidence File.</description>')
    [void]$sb.AppendLine('<language>en</language>')
    [void]$sb.AppendLine("<lastBuildDate>$newest</lastBuildDate>")
    foreach ($i in $items) {
        [void]$sb.AppendLine('<item>')
        [void]$sb.AppendLine('<title>' + (Esc $i.Title) + '</title>')
        [void]$sb.AppendLine('<link>' + $i.Link + '</link>')
        [void]$sb.AppendLine('<guid isPermaLink="true">' + $i.Link + '</guid>')
        [void]$sb.AppendLine('<pubDate>' + $i.Pub + '</pubDate>')
        [void]$sb.AppendLine('<category>' + (Esc $i.Category) + '</category>')
        [void]$sb.AppendLine('<description>' + $i.Description + '</description>')
        [void]$sb.AppendLine('</item>')
    }
    [void]$sb.AppendLine('</channel>')
    [void]$sb.AppendLine('</rss>')

    $outText = $sb.ToString()
    if ($outText -ne $raw) {
        if (-not $WhatIf) { [IO.File]::WriteAllText($rel, $outText, (New-Object System.Text.UTF8Encoding($false))) }
        Write-Output ("rss.xml rewritten: {0} items, newest {1}" -f $items.Count, $newest)
    } else {
        Write-Output ("rss.xml already in step: {0} items" -f $items.Count)
    }
    foreach ($i in $items) { Write-Output ("  {0}  {1}" -f $i.Pub, $i.Title) }

    # ---- prove it ----------------------------------------------------------
    [xml]$x = Get-Content $rel -Raw -Encoding UTF8
    $nodes = @($x.rss.channel.item)
    if ($nodes.Count -ne $stories.Count) { throw "feed has $($nodes.Count) items but $($stories.Count) stories are tracked." }
    foreach ($n in $nodes) {
        $r = $n.link.Substring($origin.Length).TrimStart('/')
        if ($tracked -notcontains $r) { throw "feed link $($n.link) is not a tracked file." }
        if ([string]::IsNullOrWhiteSpace($n.description)) { throw "empty description on $($n.link)" }
        if ([string]::IsNullOrWhiteSpace($n.pubDate)) { throw "missing pubDate on $($n.link)" }
    }

    # A page marked noindex is not for the public; it must not be syndicated.
    foreach ($n in $nodes) {
        $r = $n.link.Substring($origin.Length).TrimStart('/')
        if (Test-Path $r) {
            $t = Get-Content $r -Raw -Encoding UTF8
            if ($t -match '<meta name="robots" content="noindex') { throw "feed links a noindex page: $($n.link)" }
        }
    }
    Write-Output ("Verified: feed parses, {0} items, every link tracked, every item dated and described." -f $nodes.Count)
}
finally { Pop-Location }
