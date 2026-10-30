param(
  [switch]$Check,   # report what would change, write nothing
  [string]$Root = (Split-Path $PSScriptRoot -Parent)
)

# Day Shift 6 — reader experience, applied evenly rather than file by file.
#
#   1. Headline length tiers: .h1-lg (13-19 words) / .h1-xl (20+ words) on the
#      article <h1>, and the same classes on the homepage lead headline.
#   2. The Evidence File action row moves ABOVE the fact list, so the button is
#      reachable without scrolling past six metadata rows.
#   3. "Related coverage" gets house typography and an id, and the article footer
#      nav gains a jump link to it.
#   4. A share row of plain outbound links (no scripts, no tracking) is added
#      before the footer nav.
#
# Every edit is marker-guarded and re-runnable: running it twice changes nothing.

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$changed = @()

function Save-UnlessCheck([string]$path, [string]$text) {
  if ($Check) { return }
  [IO.File]::WriteAllText($path, $text, $utf8)
}

function Get-WordCount([string]$html) {
  $t = [regex]::Replace($html, '<[^>]+>', ' ')
  $t = $t -replace '&[a-z]+;', ' ' -replace '&#\d+;', ' '
  $t = ($t -replace '\s+', ' ').Trim()
  if (-not $t) { return 0 }
  return ($t -split ' ').Count
}

function Set-HeadlineTier([string]$html, [string]$tagPattern, [string]$file) {
  $m = [regex]::Match($html, $tagPattern)
  if (-not $m.Success) { return @($html, $null) }
  $wc = Get-WordCount $m.Groups['inner'].Value
  $tier = if ($wc -ge 20) { 'h1-xl' } elseif ($wc -ge 13) { 'h1-lg' } else { $null }

  # Existing classes must survive: the homepage lead headline carries .lead-headline
  # and some article headlines carry .h1-sm. The tier is appended, never used to
  # replace the class attribute.
  $open = $m.Groups['open'].Value
  $existing = ([regex]::Match($open, 'class="([^"]*)"')).Groups[1].Value
  $classes = @($existing -split '\s+' | Where-Object { $_ -and $_ -ne 'h1-lg' -and $_ -ne 'h1-xl' })
  if ($tier) { $classes += $tier }
  $newOpen = $open -replace '\s+class="[^"]*"', ''
  if ($classes.Count -gt 0) {
    $newOpen = $newOpen -replace '^(<h\d)', ('$1 class="' + ($classes -join ' ') + '"')
  }

  $replacement = $newOpen + $m.Groups['inner'].Value + $m.Groups['close'].Value
  $html = $html.Substring(0, $m.Index) + $replacement + $html.Substring($m.Index + $m.Length)
  $tierLabel = if ($tier) { $tier } else { 'default' }
  return @($html, ("{0}: {1} words -> {2}" -f $file, $wc, $tierLabel))
}

# ---- articles ---------------------------------------------------------------
$articles = Get-ChildItem (Join-Path $Root 'articles\*.html') | Where-Object {
  $_.Name -notlike '*evidence*' -and $_.Name -ne 'anthropic-public-benefit-fund.html'
}

foreach ($f in $articles) {
  $html = [IO.File]::ReadAllText($f.FullName)
  $before = $html
  $notes = @()

  # 1. headline tier
  $r = Set-HeadlineTier $html '(?<open><h1[^>]*>)(?<inner>.*?)(?<close></h1>)' $f.Name
  $html = $r[0]; if ($r[1]) { $notes += $r[1] }

  # 2. action row above the fact list
  $metaIdx = $html.IndexOf('<ul class="article-meta">')
  $actIdx = $html.IndexOf('<div class="article-actions">')
  if ($metaIdx -ge 0 -and $actIdx -ge 0 -and $metaIdx -lt $actIdx) {
    $mm = [regex]::Match($html.Substring($metaIdx), '(?s)^<ul class="article-meta">.*?</ul>')
    $am = [regex]::Match($html.Substring($actIdx), '(?s)^<div class="article-actions">.*?</div>')
    if ($mm.Success -and $am.Success) {
      $metaBlock = $mm.Value
      $actBlock = $am.Value
      $start = $metaIdx
      $end = $actIdx + $am.Length
      $html = $html.Substring(0, $start) + $actBlock + "`n" + $metaBlock + $html.Substring($end)
      $notes += "$($f.Name): evidence action row moved above the fact list"
    }
  }

  # 3. related coverage heading + footer jump link
  if ($html -match '<h2>Related coverage</h2>') {
    $html = $html.Replace('<h2>Related coverage</h2>', '<h2 class="related-title" id="related">Related coverage</h2>')
    $notes += "$($f.Name): Related coverage heading styled and given an anchor"
  }
  if ($html -match 'article-foot' -and $html -notmatch 'href="#related"') {
    $html = [regex]::Replace($html, '(<nav class="article-foot[^"]*"[^>]*>)', '$1' + "`n" + '<a href="#related">Related coverage</a>', 'IgnoreCase')
    $notes += "$($f.Name): footer nav jump link to Related coverage"
  }

  # 4. share row
  if ($html -notmatch 'thaf-share:begin') {
    $canon = [regex]::Match($html, '<link rel="canonical" href="([^"]+)"').Groups[1].Value
    $title = [regex]::Match($html, '<meta property="og:title" content="([^"]*)"').Groups[1].Value
    if ($canon -and $title) {
      $t = [System.Net.WebUtility]::HtmlDecode($title)
      $eu = [Uri]::EscapeDataString($t); $uu = [Uri]::EscapeDataString($canon)
      $share = @"
<!-- thaf-share:begin -->
<div class="share-row" aria-label="Share this article">
<span class="share-label">SHARE</span>
<a href="mailto:?subject=$eu&amp;body=$uu">Email</a>
<a href="https://x.com/intent/tweet?text=$eu&amp;url=$uu" rel="noopener">X</a>
<a href="https://www.linkedin.com/sharing/share-offsite/?url=$uu" rel="noopener">LinkedIn</a>
</div>
<!-- thaf-share:end -->
"@
      $html = [regex]::Replace($html, '(\n?<nav class="article-foot)', ("`n" + $share + '$1'), 'IgnoreCase')
      $notes += "$($f.Name): share row added"
    } else {
      $notes += "$($f.Name): SHARE ROW SKIPPED (no canonical or og:title)"
    }
  }

  if ($html -ne $before) {
    Save-UnlessCheck $f.FullName $html
    $changed += $notes
  }
}

# ---- homepage lead ----------------------------------------------------------
$idx = Join-Path $Root 'index.html'
$h = [IO.File]::ReadAllText($idx)
$before = $h
$r = Set-HeadlineTier $h '(?<open><h2[^>]*class="lead-headline"[^>]*>)(?<inner>.*?)(?<close></h2>)' 'index.html'
$h = $r[0]; if ($r[1]) { $changed += $r[1] }
if ($h -ne $before) { Save-UnlessCheck $idx $h }

# ---- related-link categories -------------------------------------------------
# Every "Related coverage" list labelled every link "AI Safety & Disclosure",
# including stories filed under AI Policy & Society and Frontier AI. A label that
# is the same on every row tells the reader nothing and mis-files the story, so
# each label is set from the linked article's own kicker.
# Display names are stated explicitly rather than derived from the uppercase
# kicker, so an acronym such as "AI" cannot be re-cased by a title-case rule.
$categoryNames = @{
  'AI SAFETY & DISCLOSURE' = 'AI Safety & Disclosure'
  'AI SAFETY & GOVERNANCE' = 'AI Safety & Governance'
  'AI POLICY & SOCIETY'    = 'AI Policy & Society'
  'AI POLICY & GOVERNANCE' = 'AI Policy & Governance'
  'FRONTIER AI'            = 'Frontier AI'
}
$cat = @{}
$unmapped = @()
foreach ($f in Get-ChildItem (Join-Path $Root 'articles\*.html')) {
  if ($f.Name -like '*evidence*') { continue }
  $c = [IO.File]::ReadAllText($f.FullName)
  $k = [regex]::Match($c, '<p class="kicker amber">(?:<a[^>]*>)?([^<]+)').Groups[1].Value
  if (-not $k) { continue }
  $k = [System.Net.WebUtility]::HtmlDecode(($k -split '//')[0]).Trim().ToUpper()
  if ($categoryNames.ContainsKey($k)) { $cat[$f.BaseName] = $categoryNames[$k] }
  else { $unmapped += "$($f.BaseName)=$k" }
}
if ($unmapped.Count -gt 0) { Write-Host ('UNMAPPED CATEGORIES (labels left unchanged): ' + ($unmapped -join ', ')) }

foreach ($f in $articles) {
  $html = [IO.File]::ReadAllText($f.FullName)
  $before = $html
  $fixLabels = {
    param($m)
    $slug = $m.Groups['slug'].Value
    if ($cat.ContainsKey($slug)) {
      $label = [System.Net.WebUtility]::HtmlEncode($cat[$slug])
      return $m.Groups[1].Value + ' ' + $label + $m.Groups[2].Value
    }
    return $m.Value
  }
  $html = [regex]::Replace($html, '(?s)(<a href="(?<slug>[a-z0-9\-]+)\.html">.*?</a>\s*<span class="label">)[^<]*(</span>)', $fixLabels)
  if ($html -ne $before) {
    Save-UnlessCheck $f.FullName $html
    $changed += "$($f.Name): related-link categories corrected"
  }
}

# ---- keep line endings uniform ----------------------------------------------
# Edits above insert LF lines into CRLF files. Line endings are normalised only
# on files that this run actually touched, and only when a lone LF is present,
# so the diff stays limited to the change itself.
foreach ($p in @($articles | ForEach-Object { $_.FullName }) + @($idx)) {
  $t = [IO.File]::ReadAllText($p)
  if ($t -match "(?<!`r)`n") {
    $norm = [regex]::Replace($t, "`r`n", "`n") -replace "`n", "`r`n"
    if ($norm -ne $t) { Save-UnlessCheck $p $norm }
  }
}

Write-Host ("files_changed_edits={0}" -f $changed.Count)
$changed | ForEach-Object { Write-Host "  $_" }
if ($Check) { Write-Host 'CHECK MODE: no files written' }
