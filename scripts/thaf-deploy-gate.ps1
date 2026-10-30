# ============================================================================
# THE HUMANS ARE FINE - pre-deployment gate
#
# Covers the release checks the discovery verifier and the SEO audit do not:
#   * Google Analytics configuration (items 9/10 of the release checklist)
#   * store and Etsy links
#   * canonical URL presence, uniqueness and agreement with the served path
#
# Exit code is 0 only if nothing failed. WARN items are reported but do not
# block: they are things a human should look at, not defects proven here.
#
# Two notes on scope, recorded because both caused real confusion once:
#
#  1. The site does NOT inline the gtag snippet. Every page sets
#     window.THAF_GA4_ID and loads a first-party bridge, assets/analytics.js,
#     which fetches gtag only after the reader opts in. An earlier version of
#     this script looked for the inline snippet and reported every page as a
#     failure. It now checks the mechanism the site actually uses.
#
#  2. Directory pages legitimately canonicalise to the trailing-slash URL
#     (/news/ rather than /news/index.html). The comparison below expects that,
#     so it does not warn about correct markup.
# ============================================================================
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
$pass = 0; $fail = 0; $warn = 0
function Ok($m)    { Write-Output "PASS  $m"; $script:pass++ }
function Bad($m)   { Write-Output "FAIL  $m"; $script:fail++ }
function Note($m)  { Write-Output "WARN  $m"; $script:warn++ }

try {
    $tracked = @(& git ls-files)
    $pages = @($tracked | Where-Object { $_ -match '\.html$' })

    # ---------- Google Analytics ----------
    Write-Output '--- Google Analytics ---'
    $gaPages = 0
    $gaIds = @{}
    foreach ($rel in $pages) {
        $h = [IO.File]::ReadAllText((Join-Path $repo ($rel -replace '/', '\')))
        $m = [regex]::Matches($h, 'G-[A-Z0-9]{6,12}')
        if ($m.Count -gt 0) { $gaPages++ }
        foreach ($x in $m) { if (-not $gaIds.ContainsKey($x.Value)) { $gaIds[$x.Value] = 0 }; $gaIds[$x.Value]++ }
    }
    Write-Output ("  pages carrying a GA4 id: {0} of {1}" -f $gaPages, $pages.Count)
    if ($gaIds.Count -eq 1) { Ok ("single GA4 measurement id across the tree: " + (@($gaIds.Keys)[0])) }
    elseif ($gaIds.Count -eq 0) { Bad 'no GA4 measurement id found in any page' }
    else { Note ("multiple GA4 ids in use: " + ($gaIds.Keys -join ', ')) }

    $bridgePath = Join-Path $repo 'assets\analytics.js'
    if (-not (Test-Path $bridgePath)) { Bad 'assets/analytics.js (GA bridge) is missing' }
    $bridge = if (Test-Path $bridgePath) { [IO.File]::ReadAllText($bridgePath) } else { '' }

    $gaComplete = 0
    foreach ($rel in $pages) {
        $h = [IO.File]::ReadAllText((Join-Path $repo ($rel -replace '/', '\')))
        $setId = $h -match "THAF_GA4_ID\s*=\s*'G-[A-Z0-9]{6,12}'"
        $loadsBridge = $h -match 'assets/analytics\.js'
        if ($setId -and $loadsBridge) { $gaComplete++ }
        else { Bad ("$rel : GA bridge not wired (id=$setId bridge=$loadsBridge)") }
    }
    if ($gaComplete -eq $gaPages -and $gaPages -gt 0) { Ok "THAF_GA4_ID set and analytics bridge loaded on all $gaComplete pages" }

    if ($bridge) {
        if ($bridge -match 'googletagmanager\.com/gtag/js') { Ok 'bridge fetches the gtag loader' } else { Bad 'bridge never fetches gtag' }
        if ($bridge -match "gtag\('config'") { Ok 'bridge calls gtag(config)' } else { Bad 'bridge never calls gtag config' }
        if ($bridge -match 'send_page_view') { Ok 'bridge sets send_page_view explicitly' } else { Note 'bridge does not set send_page_view' }
        if ($bridge -match 'anonymize_ip') { Ok 'bridge anonymises IP' } else { Note 'bridge does not anonymise IP' }
        if ($bridge -match 'ad_storage:\s*.denied') { Ok 'bridge denies ad storage by default' } else { Note 'bridge does not deny ad storage' }
        # The gate that matters: the gtag fetch must live inside load(), which
        # only runs on explicit consent.
        $gateIdx = $bridge.IndexOf('const load = function')
        $fetchIdx = $bridge.IndexOf('googletagmanager.com/gtag/js')
        if ($gateIdx -ge 0 -and $fetchIdx -gt $gateIdx) { Ok 'gtag fetch is inside the consent-gated load() function' }
        else { Bad 'gtag fetch is not inside load() - it may fire before consent' }
        if ($bridge -match "saved === 'granted'") { Ok 'analytics load is conditional on stored consent' } else { Note 'no stored-consent check found' }
    }

    # ---------- Store and Etsy links ----------
    Write-Output ''
    Write-Output '--- Store / Etsy links ---'
    $storeUrls = @()
    foreach ($rel in $pages) {
        $h = [IO.File]::ReadAllText((Join-Path $repo ($rel -replace '/', '\')))
        foreach ($m in [regex]::Matches($h, 'href="([^"]*(?:etsy|printify)[^"]*)"')) { $storeUrls += $m.Groups[1].Value }
    }
    $storeUrls = @($storeUrls | Sort-Object -Unique)
    if ($storeUrls.Count -eq 0) { Note 'no Etsy/Printify link found in any page' }
    foreach ($u in $storeUrls) {
        try {
            $r = Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 20 -MaximumRedirection 5
            Ok ("store link {0} {1}" -f $r.StatusCode, $u)
        } catch {
            $code = $null
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
            if ($code -in 403, 405, 429) { Note ("store link $code (bot-blocked, not proven broken): $u") }
            else { Bad ("store link $code : $u") }
        }
    }
    $storePage = @($tracked | Where-Object { $_ -match '^(store|shop)/' })
    Write-Output ("  internal store pages tracked: " + $storePage.Count + " (the store is an on-page section plus the Etsy shop link)")

    # ---------- Canonical URLs ----------
    Write-Output ''
    Write-Output '--- Canonical URLs ---'
    $seen = @{}
    $missing = 0
    foreach ($rel in $pages) {
        $h = [IO.File]::ReadAllText((Join-Path $repo ($rel -replace '/', '\')))
        $m = [regex]::Match($h, '(?i)<link\s+rel="canonical"\s+href="([^"]+)"')
        if (-not $m.Success) { $missing++; Bad "$rel : no canonical"; continue }
        $c = $m.Groups[1].Value
        if ($seen.ContainsKey($c)) { Bad ("duplicate canonical $c in $rel and " + $seen[$c]) } else { $seen[$c] = $rel }
    }
    if ($missing -eq 0) { Ok "canonical present on all $($pages.Count) pages" }
    if ($seen.Count -eq $pages.Count) { Ok "canonical URLs unique across $($pages.Count) pages" }

    # Canonical must agree with where the file is actually served.
    $mismatch = 0
    foreach ($rel in $pages) {
        $h = [IO.File]::ReadAllText((Join-Path $repo ($rel -replace '/', '\')))
        $m = [regex]::Match($h, '(?i)<link\s+rel="canonical"\s+href="([^"]+)"')
        if (-not $m.Success) { continue }
        $expect = 'https://www.thehumansarefine.com/' + ($rel -replace '(^|/)index\.html$', '$1')
        if ($rel -eq 'index.html') { $expect = 'https://www.thehumansarefine.com/' }
        if ($m.Groups[1].Value -ne $expect) { $mismatch++; Note ("canonical differs from served path: $rel -> " + $m.Groups[1].Value) }
    }
    if ($mismatch -eq 0) { Ok "every canonical matches the URL the file is served at" }

    Write-Output ''
    Write-Output ("DEPLOY GATE: PASS={0} FAIL={1} WARN={2}" -f $pass, $fail, $warn)
    if ($fail -gt 0) { exit 1 }
}
finally { Pop-Location }
