# fhc-readability.ps1 -- check the FOR HUMAN CONSUMPTION blocks against the
# approved requirements: present, labelled, ends with the sign-off exactly once,
# and written at roughly a 12-year-old reading level (Flesch-Kincaid grade).
# Read-only. Works on the local articles/ tree.

$ErrorActionPreference = 'Stop'

function Get-Syllables([string]$w) {
  $w = ($w.ToLower() -replace '[^a-z]', '')
  if ($w.Length -eq 0) { return 0 }
  if ($w.Length -le 3) { return 1 }
  $w = $w -replace '(?:[^laeiouy]es|ed|[^laeiouy]e)$', ''
  $w = $w -replace '^y', ''
  $m = [regex]::Matches($w, '[aeiouy]{1,2}')
  $n = $m.Count
  if ($n -lt 1) { $n = 1 }
  return $n
}

function Measure-Grade([string]$text) {
  $clean = $text -replace '[\u2018\u2019]', "'" -replace '[\u201C\u201D]', '"' -replace "\u2014", ' '
  $sentences = [regex]::Split($clean, '[.!?]+') | Where-Object { $_.Trim().Length -gt 0 }
  $sc = [Math]::Max(1, @($sentences).Count)
  $words = @($clean -split '\s+' | Where-Object { $_ -match '[A-Za-z]' })
  $wc = [Math]::Max(1, $words.Count)
  $syl = 0
  foreach ($w in $words) { $syl += (Get-Syllables $w) }
  $fk = 0.39 * ($wc / $sc) + 11.8 * ($syl / $wc) - 15.59
  return [pscustomobject]@{ Words = $wc; Sentences = $sc; Syllables = $syl; Grade = [Math]::Round($fk, 1) }
}

$files = Get-ChildItem 'articles\*.html' | Where-Object { $_.Name -notlike '*-evidence.html' } | Sort-Object Name
$rows = @()

foreach ($f in $files) {
  $t = Get-Content -Raw $f.FullName

  $sec = [regex]::Match($t, '(?s)<section class="hfc".*?</section>')
  if (-not $sec.Success) {
    $rows += [pscustomobject]@{ Article = $f.Name; Heading = 'NO'; Note = 'NO'; BodyGrade = ''; Words = ''; Signoffs = ''; Verdict = 'MISSING' }
    continue
  }
  $block = $sec.Value

  $hasHeading = [regex]::IsMatch($block, '(?i)<h2[^>]*>\s*FOR HUMAN CONSUMPTION\s*</h2>')
  $hasNote    = [regex]::IsMatch($block, '(?i)not reporting')
  $hasLabel   = [regex]::IsMatch($block, 'aria-labelledby="hfc-title"')

  # Body prose only -- exclude the standing note and the sign-off line.
  $body = [regex]::Match($block, '(?s)<div class="hfc-body">(.*?)</div>')
  $prose = $body.Groups[1].Value
  $prose = $prose -replace '(?s)<p class="hfc-sig">.*?</p>', ''
  $proseText = ($prose -replace '(?s)<[^>]+>', ' ') -replace '&rsquo;', "'" -replace '&mdash;', ' ' -replace '&[a-z]+;', ' '
  $proseText = ($proseText -replace '\s+', ' ').Trim()

  $signoffs = ([regex]::Matches($block, 'THE HUMANS ARE FINE\.')).Count
  $m = Measure-Grade $proseText

  $ok = $hasHeading -and $hasNote -and $hasLabel -and ($signoffs -eq 1) -and ($m.Grade -le 13)
  $rows += [pscustomobject]@{
    Article  = $f.Name
    Heading  = $(if ($hasHeading) { 'yes' } else { 'NO' })
    Note     = $(if ($hasNote) { 'yes' } else { 'NO' })
    BodyGrade= $m.Grade
    Words    = $m.Words
    Signoffs = $signoffs
    Verdict  = $(if ($ok) { 'OK' } else { 'REVIEW' })
  }
}

$rows | Format-Table -AutoSize | Out-String -Width 200 | Write-Output

$bad = @($rows | Where-Object { $_.Verdict -ne 'OK' })
Write-Output "articles: $($rows.Count)   conforming: $($rows.Count - $bad.Count)   needing review: $($bad.Count)"
$avg = ($rows | Where-Object { $_.BodyGrade -ne '' } | Measure-Object -Property BodyGrade -Average).Average
Write-Output "average Flesch-Kincaid grade: $([Math]::Round($avg,1))"
if ($bad.Count -eq 0) { Write-Output 'FHC CHECK: PASS' } else { Write-Output 'FHC CHECK: REVIEW NEEDED'; $bad | Format-Table -AutoSize | Out-String -Width 200 | Write-Output }
