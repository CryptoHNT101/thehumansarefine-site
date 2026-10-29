# ============================================================================
# THE HUMANS ARE FINE - build sitemap.xml
#
# Every <loc> is a page that is actually tracked and will actually be live.
# Every <lastmod> is the git date from page-dates.json. Nothing here is a
# guess: if a page has no date, the script fails instead of inventing one.
#
# Run scripts/thaf-page-dates.ps1 first.
# ============================================================================
param(
    [string]$DatesFile = 'page-dates.json',
    [string]$Out = 'sitemap.xml'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    $origin = 'https://www.thehumansarefine.com'
    if (-not (Test-Path $DatesFile)) { throw "Missing $DatesFile. Run scripts/thaf-page-dates.ps1 first." }
    $dates = @{}
    foreach ($r in (Get-Content $DatesFile -Raw -Encoding UTF8 | ConvertFrom-Json)) { $dates[$r.path] = $r }

    $tracked = @(git ls-files) | ForEach-Object { $_.Trim() }

    # Section pages, in the order a reader meets them. These are the site's
    # own index pages, not articles.
    $sections = @(
        'index.html',
        'news/index.html',
        'topics/frontier-ai.html',
        'topics/ai-safety.html',
        'topics/ai-agents.html',
        'topics/ai-policy.html',
        'disclosure-watch/index.html',
        'newsroom/index.html',
        'standards/index.html'
    )

    # Articles, newest first, each followed by its Evidence File.
    $articleSlugs = @($tracked |
        Where-Object { $_ -like 'articles/*.html' -and $_ -notlike '*-evidence.html' } |
        ForEach-Object { $_ -replace '^articles/', '' -replace '\.html$', '' })

    $ranked = foreach ($slug in $articleSlugs) {
        $rel = "articles/$slug.html"
        if (-not $dates.ContainsKey($rel)) { throw "No git date for $rel - cannot honestly set lastmod." }
        [pscustomobject]@{ slug = $slug; rel = $rel; when = [datetime]$dates[$rel].modified }
    }
    $ranked = @($ranked | Sort-Object when -Descending)

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($s in $sections) {
        if ($tracked -notcontains $s) { throw "$s is listed as a section page but is not tracked - it would 404." }
        $rows.Add($s)
    }
    foreach ($a in $ranked) {
        $rows.Add($a.rel)
        $ev = $a.rel -replace '\.html$', '-evidence.html'
        if ($tracked -contains $ev) { $rows.Add($ev) }
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sb.AppendLine('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')
    foreach ($rel in $rows) {
        if (-not $dates.ContainsKey($rel)) { throw "No git date for $rel - cannot honestly set lastmod." }
        $loc = if ($rel -eq 'index.html') { "$origin/" }
               elseif ($rel -match '^(.*/)index\.html$') { "$origin/$($Matches[1])" }
               else { "$origin/$rel" }
        $lastmod = ([datetime]$dates[$rel].modified).ToString('yyyy-MM-dd')
        [void]$sb.AppendLine("  <url><loc>$loc</loc><lastmod>$lastmod</lastmod></url>")
    }
    [void]$sb.AppendLine('</urlset>')

    [IO.File]::WriteAllText((Join-Path $repo $Out), $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

    # Prove it parses and every loc maps to a tracked page.
    [xml]$check = Get-Content (Join-Path $repo $Out) -Raw -Encoding UTF8
    $ns = New-Object System.Xml.XmlNamespaceManager($check.NameTable)
    $ns.AddNamespace('s', 'http://www.sitemaps.org/schemas/sitemap/0.9')
    $urls = @($check.SelectNodes('//s:url', $ns))
    foreach ($u in $urls) {
        $loc = $u.SelectSingleNode('s:loc', $ns).InnerText
        $p = $loc.Substring($origin.Length).TrimStart('/')
        if ($p -eq '' -or $p.EndsWith('/')) { $p = $p + 'index.html' }
        if ($tracked -notcontains $p) { throw "sitemap loc $loc does not map to a tracked file ($p)" }
        if (-not $u.SelectSingleNode('s:lastmod', $ns)) { throw "sitemap loc $loc has no lastmod" }
    }
    Write-Output ("sitemap written: {0} URLs, all mapped to tracked files, all with lastmod" -f $urls.Count)
}
finally { Pop-Location }
