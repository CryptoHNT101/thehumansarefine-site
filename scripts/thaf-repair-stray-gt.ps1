# Repair: collapse stray '>' runs appended after meta content attributes.
#
# Eight article pages carry tags of the form
#     <meta property="og:image" content="...png">>>>
# Browsers tolerate it, but it is malformed, and it defeated a naive parser.
# The defect is confined to runs of '>' immediately after a meta tag's content
# attribute closing quote, so the repair is narrow: collapse those runs to one '>'.
#
# The script proves its own scope: it counts offending tags before and after, and
# fails if anything is left. It does not touch any other markup.

$ErrorActionPreference = 'Stop'
$site = 'C:\Users\isaac\AppData\Roaming\ai.skynet.harness\workspaces\agent\site'
Push-Location $site

try {
    $tracked = & git ls-tree -r --name-only HEAD
    $targets = @($tracked | Where-Object { $_ -match '\.html$' })

    # A meta tag whose content attribute is followed by one or more extra '>'.
    $pattern = '(<meta\b[^>]*\bcontent="[^"]*")>(>+)'
    $totalBefore = 0
    $totalAfter = 0
    $filesChanged = 0

    foreach ($rel in $targets) {
        $full = Join-Path $site ($rel -replace '/', '\')
        if (-not (Test-Path $full)) { Write-Output "  SKIP (missing) $rel"; continue }

        $raw = [IO.File]::ReadAllText($full)
        $hits = [regex]::Matches($raw, $pattern).Count
        if ($hits -eq 0) { continue }

        $totalBefore += $hits
        $fixed = [regex]::Replace($raw, $pattern, '$1>')
        $remaining = [regex]::Matches($fixed, $pattern).Count
        $totalAfter += $remaining

        if ($remaining -ne 0) {
            Write-Output "  FAIL $rel : $remaining offending tags remain after repair"
            continue
        }

        $enc = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($full, $fixed, $enc)
        $filesChanged++
        Write-Output ("  fixed {0,-52} {1} tag(s)" -f $rel, $hits)
    }

    Write-Output ''
    Write-Output ("files changed = {0} ; tags repaired = {1} ; remaining = {2}" -f $filesChanged, $totalBefore, $totalAfter)

    # Independent re-count: no run of two or more '>' should follow a meta content quote.
    $leftover = 0
    foreach ($rel in $targets) {
        $full = Join-Path $site ($rel -replace '/', '\')
        if (-not (Test-Path $full)) { continue }
        $raw = [IO.File]::ReadAllText($full)
        $leftover += [regex]::Matches($raw, 'content="[^"]*">>').Count
    }
    Write-Output ("independent re-scan: meta tags followed by '>>' = {0}" -f $leftover)

    if ($totalAfter -eq 0 -and $leftover -eq 0) {
        Write-Output 'REPAIR: PASS'
    } else {
        Write-Output 'REPAIR: FAIL'
    }
}
finally {
    Pop-Location
}
