# ============================================================================
# THE HUMANS ARE FINE - local link, asset and page-weight check
#
# Checks the pages as they exist in this working tree (Release 2 is not
# deployed, so a live crawl would only re-prove that production is old).
# Every href/src that points inside the site must resolve to a tracked file;
# every link that leaves the site must be http(s). No network calls.
# ============================================================================
param([int]$HeavyKb = 250)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    $tracked = @(git ls-files) | ForEach-Object { $_.Trim() }
    $pages = @($tracked | Where-Object { $_ -like '*.html' })
    $fail = 0; $warn = 0; $checks = 0

    function Fail($m) { $script:fail++; Write-Output "FAIL  $m" }
    function Warn($m) { $script:warn++; Write-Output "WARN  $m" }
    function Pass($m) { }

    foreach ($rel in $pages) {
        $html = [IO.File]::ReadAllText((Join-Path $repo $rel))
        $dir = Split-Path $rel -Parent
        if (-not $dir) { $dir = '.' }

        # ---- internal references ------------------------------------------
        foreach ($m in [regex]::Matches($html, '(?i)(?:href|src)\s*=\s*"([^"]+)"')) {
            $u = $m.Groups[1].Value.Trim()
            if ($u -eq '' -or $u.StartsWith('#') -or $u.StartsWith('data:') -or $u.StartsWith('mailto:')) { continue }
            if ($u -match '^(https?:)?//') { continue }   # external, counted below
            $checks++
            $pathOnly = ($u -split '[?#]')[0]
            if ($pathOnly -eq '') { continue }
            $target = if ($pathOnly.StartsWith('/')) { $pathOnly.TrimStart('/') }
                      else { [IO.Path]::GetFullPath((Join-Path (Join-Path $repo $dir) $pathOnly)).Substring($repo.Length).TrimStart('\', '/') }
            $target = $target -replace '\\', '/'
            if ($target -eq '' -or $target.EndsWith('/')) { $target = $target + 'index.html' }
            if (-not (Test-Path (Join-Path $repo $target))) { Fail "$rel : broken internal reference '$u' -> $target" }
            elseif ($tracked -notcontains $target) { Fail "$rel : references an untracked file '$u' -> $target (404 after deploy)" }
        }

        # ---- external links use a real scheme ------------------------------
        foreach ($m in [regex]::Matches($html, '(?i)<a\s[^>]*href\s*=\s*"//[^"]+"')) {
            Fail "$rel : protocol-relative link is fragile offline: $($m.Value)"
        }

        # ---- one <h1>, a title, a canonical ---------------------------------
        $checks++
        $h1 = ([regex]::Matches($html, '(?i)<h1[\s>]')).Count
        if ($h1 -ne 1) { Fail "$rel : $h1 <h1> elements (expected 1)" }
        if ($html -notmatch '(?i)<link\s+rel="canonical"') { Fail "$rel : no canonical link" }
        if ($html -notmatch '(?i)<meta\s+property="og:image"') { Fail "$rel : no og:image" }

        # ---- weight --------------------------------------------------------
        $bytes = (Get-Item (Join-Path $repo $rel)).Length
        $kb = [Math]::Round($bytes / 1KB, 1)
        $checks++
        if ($kb -gt $HeavyKb) { Warn "$rel : HTML alone is $kb KB (over $HeavyKb KB)" }

        # ---- inline <script> size (the analytics + nav bundle is inline) ----
        $inline = 0
        foreach ($m in [regex]::Matches($html, '(?is)<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>')) { $inline += $m.Groups[1].Value.Length }
        if ($inline -gt 60000) { Warn "$rel : $([Math]::Round($inline/1KB,1)) KB of inline script" }

        # ---- duplicate meta tags (a real risk after generated blocks) ------
        foreach ($name in @('description', 'viewport', 'charset')) {
            $c = ([regex]::Matches($html, '(?i)<meta\s+(?:name|charset)\s*=?\s*"?' + $name + '"')).Count
            if ($c -gt 1) { Warn "$rel : $c '$name' meta declarations" }
        }
        foreach ($prop in @('og:title','og:description','og:url','og:image','og:type')) {
            $c = ([regex]::Matches($html, '(?i)<meta\s+property="' + [regex]::Escape($prop) + '"')).Count
            if ($c -ne 1) { Fail "$rel : $c declarations of $prop (expected 1)" }
        }
        $ld = ([regex]::Matches($html, '(?i)<script\s+type="application/ld\+json">')).Count
        if ($ld -ne 1) { Fail "$rel : $ld JSON-LD blocks (expected 1)" }
    }

    # ---- every tracked asset is referenced somewhere -----------------------
    foreach ($a in @($tracked | Where-Object { $_ -like 'assets/*' })) {
        $name = Split-Path $a -Leaf
        $used = $false
        foreach ($p in $pages) {
            if ([IO.File]::ReadAllText((Join-Path $repo $p)).Contains($name)) { $used = $true; break }
        }
        if (-not $used) { Warn "asset $a is tracked but no page references it" }
    }

    Write-Output ''
    Write-Output ("pages={0}  checks={1}  PASS={2}  FAIL={3}  WARN={4}" -f $pages.Count, $checks, ($checks - $fail), $fail, $warn)
    if ($fail -gt 0) { Write-Output 'VERDICT: FAIL'; exit 1 } else { Write-Output 'VERDICT: PASS'; exit 0 }
}
finally { Pop-Location }
