# ============================================================================
# THE HUMANS ARE FINE - fill empty <description> elements in rss.xml
#
# Every item carried an empty <description>, so a feed reader showed a
# headline with nothing under it. The summary used here is the article page's
# own meta description - the same sentence a search engine shows. Nothing new
# is written; the feed inherits copy the newspaper already stands behind.
#
# Idempotent: an item that already has a description is left alone unless its
# page copy has changed. Titles, links, guids and pubDates are untouched.
# ============================================================================
param([string]$Feed = 'rss.xml')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    $origin = 'https://www.thehumansarefine.com'
    $raw = [IO.File]::ReadAllText((Join-Path $repo $Feed))
    $filled = 0; $kept = 0; $missing = New-Object System.Collections.Generic.List[string]

    $evaluator = {
        param($m)
        $block = $m.Groups[1].Value
        $link = [regex]::Match($block, '<link>(.*?)</link>').Groups[1].Value.Trim()
        $rel = $link.Substring($origin.Length).TrimStart('/')
        $full = Join-Path $repo $rel
        if (-not (Test-Path $full)) { return $m.Value }   # left for the audit to fail on
        $html = [IO.File]::ReadAllText($full)
        $d = [regex]::Match($html, '(?is)<meta\s+name="description"\s+content="(.*?)"')
        if (-not $d.Success -or [string]::IsNullOrWhiteSpace($d.Groups[1].Value)) { return $m.Value }
        $desc = $d.Groups[1].Value.Trim()
        $desc = $desc.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
        $newBlock = [regex]::Replace($block, '(?s)<description>.*?</description>', '<description>' + $desc + '</description>')
        if ($newBlock -ne $block) { $script:filled++ } else { $script:kept++ }
        return '<item>' + $newBlock + '</item>'
    }

    $script:filled = 0; $script:kept = 0
    $out = [regex]::Replace($raw, '(?s)<item>(.*?)</item>', $evaluator)

    if ($script:filled -eq 0) {
        Write-Output "No item needed a description (already filled): $($script:kept) unchanged."
    } else {
        [IO.File]::WriteAllText((Join-Path $repo $Feed), $out, (New-Object System.Text.UTF8Encoding($false)))
        Write-Output ("Descriptions written: {0}   unchanged: {1}" -f $script:filled, $script:kept)
    }

    # prove it
    [xml]$x = Get-Content (Join-Path $repo $Feed) -Raw -Encoding UTF8
    $empty = 0
    foreach ($i in $x.rss.channel.item) { if ([string]::IsNullOrWhiteSpace($i.description)) { $empty++ } }
    if ($empty -gt 0) { throw "$empty RSS item(s) still have an empty description." }
    Write-Output ("Verified: {0} items, 0 empty descriptions, feed parses as XML." -f $x.rss.channel.item.Count)
}
finally { Pop-Location }
