# ============================================================================
# THE HUMANS ARE FINE - topic-page coverage
#
# WHY THIS EXISTS
#   Articles are published and added to sitemap, RSS and the homepage listing,
#   but the four topic archive pages are hand-maintained. They were last edited
#   at 2026-10-31 10:22, BEFORE the four reports published at 14:54 that day.
#   Those four reports currently appear on NO topic page: still crawlable from
#   the homepage and /news/, but carrying no category context.
#
#   Separately, topics/ai-policy.html advertises "3 published stories" in its
#   meta description while listing 5 - and that meta description is what a
#   search result shows.
#
# THIS SCRIPT
#   * reports which articles are missing from their topic page
#   * with -Apply, inserts the missing cards and recomputes every stated count
#     from the real number of <article class="story-card"> blocks
#
# USAGE
#   powershell -File scripts/thaf-topic-coverage.ps1           # report, exit 2 if gaps
#   powershell -File scripts/thaf-topic-coverage.ps1 -Apply     # write
#
# SOURCE LINES
#   The "SOURCE PUBLISHED ..." line cannot be derived reliably from markup, so
#   it is supplied per article in $Sources. Each entry below was read out of that
#   article's own sources block. An article with no entry is reported as
#   NEEDS-SOURCE-LINE and left alone rather than given a guessed publisher/date.
# ============================================================================
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {

  $TopicFor = [ordered]@{
    'Frontier AI' = @{ file = 'topics/frontier-ai.html'; kicker = 'FRONTIER AI // ' }
    'AI Safety'   = @{ file = 'topics/ai-safety.html';   kicker = 'AI SAFETY &amp; GOVERNANCE // ' }
    'AI Agents'   = @{ file = 'topics/ai-agents.html';   kicker = 'AI SAFETY &amp; DISCLOSURE // ' }
    'AI Policy'   = @{ file = 'topics/ai-policy.html';   kicker = 'AI POLICY &amp; SOCIETY // ' }
  }

  # Verified SOURCE PUBLISHED lines, read from each article's own sources block.
  $Sources = @{
    'ecb-ai-adoption-europe' = @{
      sub   = 'ECONOMY'
      label = 'SOURCE PUBLISHED October 30, 2026 (ECB keynote speech, Philip R. Lane)'
    }
    'ico-ai-developers-data-protection' = @{
      sub   = 'DATA PROTECTION'
      label = 'SOURCE PUBLISHED October 8, 2026 (ICO announcement)'
    }
    'uk-planning-ai-planassist' = @{
      sub   = 'GOVERNMENT'
      label = 'SOURCE PUBLISHED October 30, 2026 (GOV.UK press release, MHCLG and Angela Rayner MP)'
    }
    'aisi-protein-filtering' = @{
      sub   = 'BIOLOGICAL RISK'
      label = 'SOURCE PUBLISHED October 26, 2026 (AI Security Institute, Chem-Bio team)'
    }
  }

  function Decode([string]$s) { return [System.Net.WebUtility]::HtmlDecode($s) }
  function Encode([string]$s) {
    return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
  }

  # Robust attribute read: locate the meta tag first, then the content attribute
  # inside it. A single combined regex mis-parses when the value contains quotes
  # of the other type, which is what made an earlier attempt emit empty summaries.
  function Get-MetaContent {
    param([string]$Html, [string]$Name)
    $tag = [regex]::Match($Html, '(?is)<meta[^>]*\bname\s*=\s*(?<q>["''])' + [regex]::Escape($Name) + '\k<q>[^>]*>')
    if (-not $tag.Success) { return '' }
    $c = [regex]::Match($tag.Value, '(?is)\bcontent\s*=\s*(?<q>["''])(?<v>.*?)\k<q>')
    if (-not $c.Success) { return '' }
    return Decode($c.Groups['v'].Value)
  }

  # --- inventory -----------------------------------------------------------
  $tracked = @(git ls-files) | ForEach-Object { $_.Trim() }
  $slugs = @($tracked |
    Where-Object { $_ -like 'articles/*.html' -and $_ -notlike '*-evidence.html' } |
    ForEach-Object { $_ -replace '^articles/', '' -replace '\.html$', '' } |
    Sort-Object)

  $info = @{}
  foreach ($s in $slugs) {
    $h = Get-Content (Join-Path $repo "articles\$s.html") -Raw -Encoding UTF8
    $sec = [regex]::Match($h, '"articleSection"\s*:\s*"([^"]+)"').Groups[1].Value
    $tm = [regex]::Match($h, '(?is)<title>(.*?)</title>')
    $title = if ($tm.Success) { Decode($tm.Groups[1].Value.Trim()) } else { '' }
    $desc = Get-MetaContent -Html $h -Name 'description'
    $info[$s] = @{ section = $sec; title = $title; desc = $desc }
  }

  $totalMissing = 0
  $needsSource = New-Object System.Collections.Generic.List[string]
  $emptyDesc = New-Object System.Collections.Generic.List[string]

  foreach ($sec in $TopicFor.Keys) {
    $cfg = $TopicFor[$sec]
    $path = Join-Path $repo $cfg.file
    if (-not (Test-Path $path)) { Write-Host ("SKIP {0} - missing" -f $cfg.file); continue }
    $html = Get-Content $path -Raw -Encoding UTF8

    $present = @([regex]::Matches($html, '(?i)href="\.\./articles/([^"]+?)\.html"') |
      ForEach-Object { $_.Groups[1].Value } |
      ForEach-Object { $_ -replace '-evidence$', '' } | Select-Object -Unique)

    $expected = @($slugs | Where-Object { $info[$_].section -eq $sec })
    $missing  = @($expected | Where-Object { $present -notcontains $_ })

    $cardCount = ([regex]::Matches($html, '(?is)<article class="story-card">')).Count
    $metaCount = [regex]::Match($html, '(?is)<meta\s+name="description"\s+content="(\d+) published stories')
    $metaN = if ($metaCount.Success) { [int]$metaCount.Groups[1].Value } else { -1 }

    Write-Host ''
    Write-Host ("=== {0}  ({1})" -f $cfg.file, $sec)
    Write-Host ("    cards on page       : {0}" -f $cardCount)
    Write-Host ("    meta desc says      : {0}" -f $(if ($metaN -ge 0) { $metaN } else { '(n/a)' }))
    Write-Host ("    articles in section : {0}" -f $expected.Count)
    Write-Host ("    missing from page   : {0}" -f $missing.Count)
    $missing | ForEach-Object { Write-Host ("      - " + $_) }
    if ($metaN -ge 0 -and $metaN -ne $cardCount -and $missing.Count -eq 0) {
      Write-Host ("    COUNT-MISMATCH: meta description says {0}, page lists {1}" -f $metaN, $cardCount)
    }

    $nothingToDo = ($missing.Count -eq 0 -and ($metaN -lt 0 -or $metaN -eq $cardCount))
    if ($nothingToDo) { Write-Host '    OK - coverage and every stated count agree'; continue }

    if (-not $Apply) { $totalMissing += $missing.Count; continue }

    # --- build ONE card block so order is preserved -----------------------
    $cards = New-Object System.Collections.Generic.List[string]
    foreach ($s in $missing) {
      if (-not $Sources.ContainsKey($s)) { $needsSource.Add(("{0} (on {1})" -f $s, $cfg.file)); continue }
      if ([string]::IsNullOrWhiteSpace($info[$s].desc)) { $emptyDesc.Add(("{0} (on {1})" -f $s, $cfg.file)); continue }
      $src = $Sources[$s]
      $cards.Add(@(
        '<article class="story-card">',
        ('<p class="kicker">' + $cfg.kicker + $src.sub + '</p>'),
        ('<h3><a href="../articles/' + $s + '.html">' + (Encode $info[$s].title) + '</a></h3>'),
        ('<p>' + (Encode $info[$s].desc) + '</p>'),
        ('<p class="label">' + $src.label + '</p>'),
        ('<p class="label">EVIDENCE FILE PUBLISHED &middot; <a class="text-link" href="../articles/' + $s + '-evidence.html">Evidence File</a></p>'),
        '</article>'
      ) -join "`n")
    }

    if ($cards.Count -gt 0) {
      $anchor = '<div class="cards">'
      $at = $html.IndexOf($anchor)
      if ($at -lt 0) { throw "no <div class=`"cards`"> wrapper in $($cfg.file)" }
      $cut = $at + $anchor.Length
      $block = "`n" + ($cards -join "`n")
      $html = $html.Substring(0, $cut) + $block + $html.Substring($cut)
    }

    # --- recompute every stated count from real cards ---------------------
    $newCardCount = ([regex]::Matches($html, '(?is)<article class="story-card">')).Count
    $html = [regex]::Replace($html,
      '(?is)<p class="kicker">\d+ published stories under this heading\.</p>',
      ('<p class="kicker">' + $newCardCount + ' published stories under this heading.</p>'))
    foreach ($attr in @('description', 'og:description', 'twitter:description')) {
      $prop = if ($attr -eq 'description') { 'name' } else { 'property' }
      $html = [regex]::Replace($html,
        ('(?is)(<meta\s+' + $prop + '="' + [regex]::Escape($attr) + '"\s+content=")\d+( published stories)'),
        ('${1}' + $newCardCount + '${2}'))
    }
    $html = [regex]::Replace($html, '("description":")\d+( published stories)', ('${1}' + $newCardCount + '${2}'))

    [IO.File]::WriteAllText($path, $html, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("    APPLIED: inserted {0} card(s); cards now {1}; all stated counts now {2}" -f $cards.Count, $newCardCount, $newCardCount)
    $totalMissing += $missing.Count
  }

  if ($needsSource.Count -gt 0) {
    Write-Host ''
    Write-Host 'NEEDS-SOURCE-LINE (left untouched rather than guessed):'
    $needsSource | ForEach-Object { Write-Host ('  - ' + $_) }
  }
  if ($emptyDesc.Count -gt 0) {
    Write-Host ''
    Write-Host 'EMPTY-DESCRIPTION (article has no usable meta description):'
    $emptyDesc | ForEach-Object { Write-Host ('  - ' + $_) }
  }

  if (-not $Apply -and $totalMissing -gt 0) {
    Write-Host ''
    Write-Host ("TOTAL MISSING CARDS = {0}. Re-run with -Apply to fix." -f $totalMissing)
    exit 2
  }
  if (-not $Apply) { Write-Host ''; Write-Host 'COVERAGE OK - no missing cards, no count mismatch.' }
}
finally { Pop-Location }
