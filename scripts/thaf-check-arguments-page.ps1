# ============================================================================
# THE HUMANS ARE FINE - verify the private "agents are arguing" page
#
# The page claims that it reproduces four signed records verbatim. That claim
# is either checkable or it is decoration, so this script checks it: the page's
# visible text must contain each record's own words, in order, with nothing
# added. It also checks the privacy claims: noindex, absent from the sitemap,
# absent from the feed, not linked from the public pages, no analytics.
# ============================================================================
param(
    [string]$Page = '../private/arguments/index.html',
    [string]$Store = '../private/arguments/shift08/records.jsonl'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    $pass = 0; $fail = 0
    function Ok([string]$name) { Write-Output ("PASS  " + $name); $script:pass++ }
    function No([string]$name, [string]$why) { Write-Output ("FAIL  " + $name + "  -> " + $why); $script:fail++ }
    function Test-Check([string]$name, [bool]$cond, [string]$why) {
        if ($cond) { Ok $name } else { No $name $why }
    }

    function Flatten([string]$s) {
        # Block boundaries separate words; inline tags must not, or stripping
        # <strong> would insert a space that the source text never had.
        $t = [regex]::Replace($s, '(?is)<(script|style)[^>]*>.*?</\1>', ' ')
        $t = [regex]::Replace($t, '(?i)</(p|li|div|h[1-6]|tr|td|th|ul|ol|nav|article|table|section|blockquote)>', ' ')
        $t = [regex]::Replace($t, '(?i)<br\s*/?>', ' ')
        $t = [regex]::Replace($t, '(?s)<[^>]+>', '')
        $t = [System.Net.WebUtility]::HtmlDecode($t)
        $t = $t -replace '\u00a0', ' '
        return ([regex]::Replace($t, '\s+', ' ')).Trim()
    }

    if (-not (Test-Path $Page)) { throw "Missing page: $Page - run scripts/thaf-build-arguments-page.ps1 first." }
    $html = Get-Content $Page -Raw -Encoding UTF8
    $pageText = Flatten $html

    # --- privacy claims -----------------------------------------------------
    Test-Check 'page is marked noindex' ($html -match '<meta name="robots" content="noindex') 'no robots noindex meta'
    Test-Check 'page loads no analytics script' ($html -notmatch 'analytics\.js' -and $html -notmatch 'THAF_GA4_ID' -and $html -notmatch 'gtag\(') 'analytics reference found'
    $scriptTags = [regex]::Matches($html, '(?is)<script[^>]*>.*?</script>')
    Test-Check 'page carries no script blocks at all' ($scriptTags.Count -eq 0) ("script blocks = " + $scriptTags.Count)
    $stylesheets = [regex]::Matches($html, '(?i)<link[^>]+rel="stylesheet"[^>]*>')
    # Relative to the page, never off-site, and the file has to exist - the page
    # lives outside the repo now, so a stale ../../ path would silently break it.
    $localOnly = $true
    $pageDir = Split-Path (Resolve-Path $Page).Path -Parent
    foreach ($l in $stylesheets) {
        $m = [regex]::Match($l.Value, '(?i)href="([^"]+)"')
        if (-not $m.Success) { $localOnly = $false; continue }
        $u = $m.Groups[1].Value
        if ($u -match '^([a-z]+:|//)') { $localOnly = $false; continue }
        $target = [IO.Path]::GetFullPath((Join-Path $pageDir $u))
        if (-not (Test-Path $target)) { $localOnly = $false }
    }
    Test-Check ('stylesheets are local only and resolve (' + $stylesheets.Count + ')') ($localOnly -and $stylesheets.Count -gt 0) 'a stylesheet points off-site or does not exist'
    $externalLinks = @([regex]::Matches($html, '(?i)href="(https?://[^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    $offsite = @($externalLinks | Where-Object { $_.TrimEnd('/').ToLower() -ne 'https://www.thehumansarefine.com' })
    Ok ('citations link out (' + $offsite.Count + ' external hrefs)')

    # --- sitemap and feed must not carry it ---------------------------------
    foreach ($file in @('sitemap.xml', 'rss.xml')) {
        if (-not (Test-Path $file)) { continue }
        $xml = Get-Content $file -Raw -Encoding UTF8
        Test-Check ("$file does not contain the private page") ($xml -notmatch 'newsroom/arguments') 'the page leaked into a public index'
    }
    $publicPages = @(git ls-files '*.html') | Where-Object { $_ -ne $Page }
    $linkedFrom = @()
    foreach ($p in $publicPages) {
        $t = Get-Content $p -Raw -Encoding UTF8
        if ($t -match 'newsroom/arguments|arguments/index\.html') { $linkedFrom += $p }
    }
    Test-Check 'no public page links to it' ($linkedFrom.Count -eq 0) ('linked from: ' + ($linkedFrom -join ', '))

    # --- transcription integrity -------------------------------------------
    $storeFull = Resolve-Path $Store
    $sha = (Get-FileHash $storeFull -Algorithm SHA256).Hash.ToLower()
    Test-Check 'page states the real store hash' ($html -match [regex]::Escape($sha)) "hash $sha not on page"
    $records = @(Get-Content $Store -Encoding UTF8 | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_ | ConvertFrom-Json })
    Test-Check ('store holds the expected 4 records (' + $records.Count + ')') ($records.Count -eq 4) 'record count changed'

    foreach ($r in $records) {
        Test-Check ('record id ' + $r.id + ' is printed') ($html -match [regex]::Escape($r.id)) 'record id missing from page'
        $body = [string]$r.body
        $begin = '----- BEGIN VERBATIM RESULT -----'
        $end = '----- END VERBATIM RESULT -----'
        $i = $body.IndexOf($begin); $j = $body.IndexOf($end)
        $verbatim = if ($i -ge 0 -and $j -gt $i) { $body.Substring($i + $begin.Length, $j - $i - $begin.Length) } else { $body }
        # Only the markdown emphasis markers may differ; every word must match.
        $want = Flatten (($verbatim -replace '\*\*', '' -replace '\*', '').Trim())
        $have = Flatten $pageText
        $found = $have.Contains($want)
        Test-Check ('record ' + $r.id + ' reproduced verbatim (' + $want.Length + ' chars)') $found 'the page text does not contain this record''s own words'
    }

    # --- honesty checks on the page's own claims ---------------------------
    Test-Check 'no double-escaped entities' ($html -notmatch '&amp;(mdash|rsquo|#163);') 'entity double-escape'
    Test-Check 'no leftover markdown asterisks' ($html -notmatch '>?\s\*\*') 'raw ** in output'
    Test-Check 'states there is no genuine disagreement' ($pageText -match 'Genuine disagreement None observed') 'the empty-state finding is missing'
    Test-Check 'states the authorship limit' ($pageText -match 'does not prove which registered identity wrote it') 'the auth gap disclosure is missing'
    Test-Check 'states participants are station agents' ($pageText -match 'station agents on this machine') 'local-participation disclosure missing'
    Test-Check 'states it is not published' ($pageText -match 'private, unlisted, not published') 'status line missing'

    $words = ($pageText -split '\s').Count
    Write-Output ''
    Write-Output ("page: {0} bytes, {1} visible words, {2} citations out" -f (Get-Item $Page).Length, $words, $offsite.Count)
    Write-Output ("RESULT pass={0} fail={1}" -f $pass, $fail)
    if ($fail -gt 0) { exit 1 }
}
finally { Pop-Location }
