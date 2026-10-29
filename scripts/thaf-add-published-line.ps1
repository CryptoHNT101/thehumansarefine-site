# ============================================================================
# THE HUMANS ARE FINE - show the publication date on the page
#
# Every news story carried its date in the markup (JSON-LD, og, sitemap, feed)
# and nowhere a reader could see it. "Source published" is the SOURCE's date,
# which is a different fact and must not be mistaken for ours.
#
# The date comes from scripts/page-dates.json, which is derived from git. If a
# page has no date there, this script leaves it alone and says so - a guessed
# publication date is a lie with a timestamp on it.
# ============================================================================
param(
    [string]$DatesFile = 'scripts/page-dates.json',
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    $datesPath = if ([IO.Path]::IsPathRooted($DatesFile)) { $DatesFile } else { Join-Path $repo $DatesFile }
    if (-not (Test-Path $datesPath)) { throw ("Missing dates file: " + $datesPath + " - run scripts/thaf-page-dates.ps1 first.") }
    $dates = @{}
    foreach ($r in (Get-Content $datesPath -Raw -Encoding UTF8 | ConvertFrom-Json)) { $dates[$r.path] = $r }

    $pages = @(git ls-files 'articles/*.html' | Where-Object { $_ -notlike '*-evidence.html' })
    $changed = 0; $same = 0; $skipped = 0

    foreach ($rel in $pages) {
        if (-not $dates.ContainsKey($rel)) { Write-Output ("SKIP  $rel - no git date on record"); $skipped++; continue }
        $when = [datetimeoffset]::Parse($dates[$rel].published, [Globalization.CultureInfo]::InvariantCulture)
        $label = $when.ToString('MMMM d, yyyy', [Globalization.CultureInfo]::InvariantCulture)
        $file = Join-Path $repo $rel
        $text = [IO.File]::ReadAllText($file)
        if ($text -match '<li><b>Published</b>') { $same++; continue }

        $anchor = '<ul class="article-meta">'
        $at = $text.IndexOf($anchor)
        if ($at -lt 0) { Write-Output ("SKIP  $rel - no ul.article-meta"); $skipped++; continue }
        $insert = $anchor + "`r`n<li><b>Published</b> $label</li>"
        $new = $text.Substring(0, $at) + $insert + $text.Substring($at + $anchor.Length)

        if ($WhatIf) {
            Write-Output ("WhatIf $rel -> Published $label")
        }
        else {
            [IO.File]::WriteAllText($file, $new, (New-Object System.Text.UTF8Encoding($false)))
            Write-Output ("ok    $rel -> Published $label")
            $changed++
        }
    }
    Write-Output ("published lines: added=$changed already=$same skipped=$skipped")
}
finally { Pop-Location }
