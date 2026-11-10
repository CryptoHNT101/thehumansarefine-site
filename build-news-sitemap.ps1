<#
.SYNOPSIS
  Regenerate news-sitemap.xml from the published articles' own original
  publication timestamps, keeping only URLs inside Google's two-day window.

.DESCRIPTION
  Google's current guidance (News sitemap, read 2026-11-09):
    "Only include recent URLs for articles that were created in the last two days.
     Once the articles are older than two days, either remove those URLs from the
     news sitemap or remove the news:news metadata."

  Before this script, news-sitemap.xml was maintained by hand. It carried four
  entries on 2026-11-09, three of them outside the window, and drifted again the
  moment the newest article passed 48 hours. This makes the trim mechanical.

  Rules enforced here:
    - The only source of a date is each article's own JSON-LD datePublished.
      Nothing is rewritten, rounded, re-based or back-dated.
    - An article is included only when it is inside the window; the comparison is
      made in UTC so the host timezone cannot move the boundary.
    - Output order is newest first, so the file is stable between runs.
    - An empty window produces a valid empty urlset, never an empty or broken file.

  This script never publishes. It writes one file in the working tree; committing
  and deploying stay with the Commander.

.PARAMETER Now
  Override "now" for deterministic tests. Accepts any ISO-8601 string.

.PARAMETER WindowHours
  Window size. Defaults to 48, per Google's "last two days".

.PARAMETER DryRun
  Report what would be written without touching the file.
#>
[CmdletBinding()]
param(
    [string] $RepoRoot    = (Get-Location).Path,
    [string] $OutFile     = 'news-sitemap.xml',
    [string] $Now,
    [int]    $WindowHours = 48,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture

if ([string]::IsNullOrWhiteSpace($Now)) {
    $nowDto = [datetimeoffset]::UtcNow
} else {
    $nowDto = [datetimeoffset]::Parse($Now, $inv)
}

$articlesDir = Join-Path $RepoRoot 'articles'
if (-not (Test-Path $articlesDir)) { throw "articles directory not found under $RepoRoot" }

function Convert-ToXmlText([string] $s) {
    if ($null -eq $s) { return '' }
    return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&apos;')
}

# Pull one JSON-LD string field without a JSON dependency, so the script has no
# module requirements on the build host.
function Get-JsonLdField([string] $html, [string] $field) {
    $m = [regex]::Match($html, '"' + [regex]::Escape($field) + '"\s*:\s*"((?:[^"\\]|\\.)*)"')
    if (-not $m.Success) { return $null }
    $raw = $m.Groups[1].Value
    # Undo the JSON escapes that can legitimately appear in a headline.
    return [regex]::Replace($raw, '\\u([0-9a-fA-F]{4})', {
            param($x) [char][Convert]::ToInt32($x.Groups[1].Value, 16)
        }).Replace('\"', '"').Replace("\\", '\').Replace('\/', '/')
}

$rows = New-Object System.Collections.Generic.List[object]
$skipped = New-Object System.Collections.Generic.List[string]

$articleList = @(Get-ChildItem $articlesDir -Filter *.html | Where-Object { $_.Name -notlike '*-evidence.html' })
$articleTotal = $articleList.Count

foreach ($f in $articleList) {
    $html = Get-Content $f.FullName -Raw -Encoding UTF8

    $published = Get-JsonLdField $html 'datePublished'
    $headline  = Get-JsonLdField $html 'headline'

    if ([string]::IsNullOrWhiteSpace($published)) { $skipped.Add($f.Name + ' (no datePublished)'); continue }
    if ([string]::IsNullOrWhiteSpace($headline))  { $skipped.Add($f.Name + ' (no headline)');    continue }

    try {
        $dto = [datetimeoffset]::Parse($published, $inv)
    } catch {
        $skipped.Add($f.Name + ' (unparseable date: ' + $published + ')')
        continue
    }

    $ageHours = ($nowDto.ToUniversalTime() - $dto.ToUniversalTime()).TotalHours
    if ($ageHours -lt 0) {
        # A future date is a data error, not a fresh article. Never surface it.
        $skipped.Add($f.Name + ' (future date: ' + $published + ')')
        continue
    }
    if ($ageHours -gt $WindowHours) { continue }

    $rows.Add([pscustomobject]@{
            Slug      = $f.BaseName
            Loc       = 'https://www.thehumansarefine.com/articles/' + $f.Name
            Published = $published        # verbatim, never reformatted
            Dto       = $dto
            Headline  = $headline
            AgeHours  = $ageHours
        })
}

$ordered = $rows | Sort-Object Dto -Descending

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sb.AppendLine('<!--')
[void]$sb.AppendLine('  News sitemap. Google News: "Only include recent URLs for articles that were created in the')
[void]$sb.AppendLine('  last two days. Once the articles are older than two days, either remove those URLs from the')
[void]$sb.AppendLine('  news sitemap or remove the news:news metadata."')
[void]$sb.AppendLine('  (https://developers.google.com/search/docs/crawling-indexing/sitemaps/news-sitemap)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('  GENERATED by build-news-sitemap.ps1 - do not hand-edit.')
[void]$sb.AppendLine('  Window anchor (UTC): ' + $nowDto.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', $inv))
[void]$sb.AppendLine('  Window: ' + $WindowHours + ' hours. Publication dates are copied verbatim from each')
[void]$sb.AppendLine('  article''s own JSON-LD datePublished and are never rewritten or re-based.')
[void]$sb.AppendLine('  Older reporting stays in sitemap.xml; it is only removed from THIS file.')
[void]$sb.AppendLine('-->')
[void]$sb.AppendLine('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"')
[void]$sb.AppendLine('        xmlns:news="http://www.google.com/schemas/sitemap-news/0.9">')
foreach ($r in $ordered) {
    [void]$sb.AppendLine('  <url>')
    [void]$sb.AppendLine('    <loc>' + (Convert-ToXmlText $r.Loc) + '</loc>')
    [void]$sb.AppendLine('    <news:news>')
    [void]$sb.AppendLine('      <news:publication>')
    [void]$sb.AppendLine('        <news:name>THE HUMANS ARE FINE</news:name>')
    [void]$sb.AppendLine('        <news:language>en</news:language>')
    [void]$sb.AppendLine('      </news:publication>')
    [void]$sb.AppendLine('      <news:publication_date>' + $r.Published + '</news:publication_date>')
    [void]$sb.AppendLine('      <news:title>' + (Convert-ToXmlText $r.Headline) + '</news:title>')
    [void]$sb.AppendLine('    </news:news>')
    [void]$sb.AppendLine('  </url>')
}
[void]$sb.AppendLine('</urlset>')

$xml = $sb.ToString()

# Validate before writing: a malformed sitemap is worse than a stale one.
$doc = New-Object System.Xml.XmlDocument
$doc.LoadXml($xml)
$locCount = ([regex]::Matches($xml, '<loc>')).Count
$dateCount = ([regex]::Matches($xml, '<news:publication_date>')).Count
if ($locCount -ne $dateCount) { throw "generated sitemap has $locCount locs but $dateCount dates" }
$included = @($ordered).Count
if ($locCount -ne $included) { throw "generated sitemap has $locCount locs but $included rows" }

Write-Output ('WINDOW      {0}h  anchor={1}' -f $WindowHours, $nowDto.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', $inv))
Write-Output ('INCLUDED    {0}' -f $included)
foreach ($r in @($ordered)) {
    Write-Output ('   {0}  age={1:n1}h  {2}' -f $r.Published, $r.AgeHours, $r.Slug)
}
$excludedOld = $articleTotal - $included - $skipped.Count
Write-Output ('EXCLUDED_OLD {0}  (total articles {1})' -f $excludedOld, $articleTotal)
if ($skipped.Count -gt 0) {
    Write-Output ('SKIPPED_INVALID {0}' -f $skipped.Count)
    foreach ($s in $skipped) { Write-Output ('   ' + $s) }
}

$target = Join-Path $RepoRoot $OutFile
if ($DryRun) {
    Write-Output ('DRYRUN      would write {0} bytes to {1}' -f $xml.Length, $target)
} else {
    [IO.File]::WriteAllText($target, $xml, (New-Object Text.UTF8Encoding($false)))
    Write-Output ('WROTE       {0} bytes to {1}' -f $xml.Length, $target)
}
Write-Output ('PARSE_OK    locs={0} dates={1}' -f $locCount, $dateCount)
