# ===========================================================================
# THAF - wire the agent-participation endpoint configuration into every page
# ---------------------------------------------------------------------------
# Adds <script src="<prefix>assets/ap-config.js"> immediately before the
# ap-core.js tag on every page that already loads the participation surfaces.
#
# Two jobs, one script:
#   -NoApiBase        wire the tag only (leaves ap-config.js at its current value)
#   -ApiBase <origin> also set the endpoint in assets/ap-config.js
#
# Idempotent: a page that already has the tag is reported as 'already' and is
# not touched. That matters because this runs on a 20-page tree and a second
# run must not double-insert.
#
# It never invents a prefix. The prefix is copied from the existing ap-core.js
# src on the same page, so a page at /articles/ keeps ../assets/ and a page at
# the root keeps assets/.
# ===========================================================================
param(
    [string]$Root = '',
    [string]$ApiBase = '',
    [string]$ConfigFile = ''
)

$ErrorActionPreference = 'Stop'

if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
if (-not $ConfigFile) { $ConfigFile = Join-Path $Root 'assets\ap-config.js' }

if (-not (Test-Path -LiteralPath (Join-Path $Root 'assets\ap-core.js'))) {
    Write-Host ('FATAL: no assets\ap-core.js under ' + $Root)
    exit 1
}
if (-not (Test-Path -LiteralPath $ConfigFile)) {
    Write-Host ('FATAL: no config file at ' + $ConfigFile)
    exit 1
}

# ---- 1. optionally set the endpoint -----------------------------------------
if ($ApiBase) {
    $clean = $ApiBase.Trim().TrimEnd('/')
    if ($clean -notmatch '^https://[^/\s]+$' -and $clean -notmatch '^http://(127\.0\.0\.1|localhost)(:\d+)?$') {
        Write-Host ('FATAL: -ApiBase must be an https origin, or http on loopback only. Got: ' + $ApiBase)
        exit 1
    }
    $cfg = [System.IO.File]::ReadAllText($ConfigFile)
    $esc = $clean.Replace('\', '\\').Replace("'", "\'")
    $pattern = "(?m)^(?<indent>\s*)global\.THAF_AGENT_API\s*=\s*'[^']*';\s*$"
    if ($cfg -notmatch $pattern) {
        Write-Host 'FATAL: could not find the assignment line in ap-config.js'
        exit 1
    }
    $cfg = [regex]::Replace($cfg, $pattern, ('${indent}global.THAF_AGENT_API = ''' + $esc + ''';'), 1)
    [System.IO.File]::WriteAllText($ConfigFile, $cfg, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ('ap-config.js endpoint set to: ' + $clean)
}

# ---- 2. wire every page that loads the surfaces -----------------------------
$pages = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.html' |
    Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|preview-verification)[\\/]' }

$added = 0; $already = 0; $skipped = 0
foreach ($p in $pages) {
    $text = [System.IO.File]::ReadAllText($p.FullName)
    if ($text -notmatch 'ap-core\.js') { $skipped++; continue }

    if ($text -match 'ap-config\.js') {
        Write-Host ('  already   ' + $p.FullName.Replace($Root, ''))
        $already++
        continue
    }

    # Copy the asset prefix from the page's own ap-core.js reference.
    $m = [regex]::Match($text, '<script\s+src="([^"]*)ap-core\.js[^"]*"')
    if (-not $m.Success) {
        Write-Host ('  NO PREFIX ' + $p.FullName.Replace($Root, ''))
        continue
    }
    $prefix = $m.Groups[1].Value

    $tag = '<script src="' + $prefix + 'ap-config.js?v=agent05"></script>' + "`r`n"
    $text = [regex]::Replace($text, '(<script\s+src="' + [regex]::Escape($prefix) + 'ap-core\.js)', ($tag + '$1'), 1)
    [System.IO.File]::WriteAllText($p.FullName, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ('  wired     ' + $p.FullName.Replace($Root, '') + '   (prefix "' + $prefix + '")')
    $added++
}

Write-Host ''
Write-Host ('PAGES wired={0} already={1} without-surfaces={2}' -f $added, $already, $skipped)
if ($added -gt 0 -or $already -gt 0) { exit 0 } else { Write-Host 'NOTHING WIRED'; exit 1 }
