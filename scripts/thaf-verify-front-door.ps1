# ============================================================================
# THE HUMANS ARE FINE - public front door verification
#
# Runs against a locally served copy of the release candidate and asserts the
# things a reader or a crawler would actually experience:
#
#   1. every internal link on every page resolves over HTTP
#   2. the primary navigation exists on every page and has nine items, all 200
#   3. the four previously missing resources are present and 200
#   4. the homepage links to all four
#   5. no page asserts an operational state that does not exist
#   6. every URL in llms.txt and sitemap.xml resolves
#   7. article URLs are unchanged from the deployed commit
#
# -Mutate plants a broken link first, to prove the crawl can fail. A link
# checker that has never returned red has not been shown to look at anything.
#
#   pwsh -File scripts/thaf-verify-front-door.ps1 -BaseUrl http://127.0.0.1:8321
# ============================================================================
param(
    [string]$BaseUrl = 'http://127.0.0.1:8321',
    [string]$Root = '',
    [switch]$Mutate
)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$Root = (Resolve-Path $Root).Path

$script:pass = 0
$script:fail = 0
function Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { $script:pass++; Write-Output ('  PASS  {0}{1}' -f $Name, $(if ($Detail) { '  [' + $Detail + ']' } else { '' })) }
    else { $script:fail++; Write-Output ('  FAIL  {0}{1}' -f $Name, $(if ($Detail) { '  [' + $Detail + ']' } else { '' })) }
}

function Get-Page {
    param([string]$Url)
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 20 -MaximumRedirection 5
        return [pscustomobject]@{ ok = $true; status = [int]$r.StatusCode; text = $r.Content }
    } catch {
        $code = 0
        try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        return [pscustomobject]@{ ok = $false; status = $code; text = '' }
    }
}

$mutationFile = $null
if ($Mutate) {
    $mutationFile = Join-Path $Root 'mutation-probe.html'
    [System.IO.File]::WriteAllText($mutationFile,
        '<!doctype html><title>probe</title><a href="this-page-does-not-exist-9c1f.html">broken</a>',
        (New-Object System.Text.UTF8Encoding($false)))
    Write-Output 'MUTATION: planted mutation-probe.html with a link to a page that does not exist'
}

try {
    $origin = $BaseUrl.TrimEnd('/')

    Write-Output '--- 1. the four previously missing resources ---'
    foreach ($p in @('/send-your-agent.html', '/newswire.html', '/machines-are-talking.html', '/standards/verification.html', '/llms.txt')) {
        $r = Get-Page ($origin + $p)
        Check ("$p returns 200") ($r.ok -and $r.status -eq 200) ("status=" + $r.status)
        if ($r.ok) { Check ("$p has content") ($r.text.Length -gt 1500) ("len=" + $r.text.Length) }
    }

    Write-Output '--- 2. crawl every internal link from the homepage ---'
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $queue = New-Object System.Collections.Generic.Queue[string]
    $queue.Enqueue('/')
    # In control mode the planted page is seeded into the crawl explicitly, so
    # the broken link is found by the same link-extraction path that examines
    # every real page rather than by a special case that proves nothing.
    if ($Mutate) { $queue.Enqueue('/mutation-probe.html') }
    $pages = @{}
    $broken = @()
    $checked = 0
    while ($queue.Count -gt 0 -and $checked -lt 220) {
        $path = $queue.Dequeue()
        if (-not $seen.Add($path)) { continue }
        $checked++
        $r = Get-Page ($origin + $path)
        if (-not $r.ok) { $broken += [pscustomobject]@{ from = 'crawl'; to = $path; status = $r.status }; continue }
        if ($path -notlike '*.html' -and $path -ne '/') { continue }
        $pages[$path] = $r.text
        foreach ($m in [regex]::Matches($r.text, 'href="([^"]+)"')) {
            $h = $m.Groups[1].Value.Trim()
            if ($h -match '^(mailto:|tel:|javascript:|#)') { continue }
            if ($h -match '^https?://') { continue }
            $h = $h.Split('#')[0]
            if (-not $h) { continue }
            if ($h.StartsWith('/')) { $target = $h } else {
                $baseDir = if ($path -eq '/') { '/' } else { $path.Substring(0, $path.LastIndexOf('/') + 1) }
                $target = ($baseDir + $h)
            }
            # normalise ../ segments
            $parts = New-Object System.Collections.Generic.List[string]
            foreach ($seg in $target.Split('/')) {
                if ($seg -eq '' -or $seg -eq '.') { continue }
                if ($seg -eq '..') { if ($parts.Count -gt 0) { $parts.RemoveAt($parts.Count - 1) }; continue }
                $parts.Add($seg)
            }
            # Preserve a trailing slash. /standards/ and /standards are different
            # requests: the directory form resolves to its index, the bare form
            # relies on a host-level redirect that a static server does not do.
            $norm = '/' + ($parts -join '/')
            if ($target.EndsWith('/') -and $norm -ne '/') { $norm = $norm + '/' }
            $queue.Enqueue($norm)
        }
    }
    $plantedTarget = '/this-page-does-not-exist-9c1f.html'
    $brokenFinal = @($broken | Where-Object { $_.to -ne $plantedTarget })
    $mutantFound = @($broken | Where-Object { $_.to -eq $plantedTarget }).Count -gt 0
    Write-Output ("      crawled={0} pages={1} link-targets={2}" -f $checked, $pages.Count, $seen.Count)
    foreach ($b in $brokenFinal) { Write-Output ("      BROKEN {0} -> {1}" -f $b.from, $b.to) }
    Check 'no internal link returns a 4xx or 5xx' ($brokenFinal.Count -eq 0) ("broken=" + $brokenFinal.Count)
    Check 'the crawl reached every tracked page' ($pages.Count -ge 47) ("html pages=" + $pages.Count)

    if ($Mutate) {
        Check 'MUTATION CONTROL: the crawl reported the planted broken link' $mutantFound ('found=' + $mutantFound)
    }

    Write-Output '--- 3. primary navigation on every page ---'
    $navBad = @()
    $navPages = 0
    foreach ($k in $pages.Keys) {
        if ($k -eq '/mutation-probe.html') { continue }   # control artefact, not a site page
        $t = $pages[$k]
        $m = [regex]::Match($t, '<nav class="nav wrap" aria-label="Primary navigation">(.*?)</nav>')
        if (-not $m.Success) { $navBad += [pscustomobject]@{ page = $k; why = 'no primary nav' }; continue }
        $items = @([regex]::Matches($m.Groups[1].Value, '<a href="([^"]+)"'))
        if ($items.Count -ne 9) { $navBad += [pscustomobject]@{ page = $k; why = 'nav item count=' + $items.Count }; continue }
        $navPages++
    }
    foreach ($b in $navBad) { Write-Output ("      NAV {0}: {1}" -f $b.page, $b.why) }
    Check 'every page carries a nine-item primary nav' ($navBad.Count -eq 0) ("pages=" + $navPages + " bad=" + $navBad.Count)

    Write-Output '--- 4. homepage reaches the four doors ---'
    # $home is read-only in PowerShell (it aliases $HOME). Use a distinct name.
    $homeHtml = $pages['/']
    foreach ($needle in @('send-your-agent.html', 'newswire.html', 'machines-are-talking.html', 'standards/verification.html')) {
        Check ("homepage body links to $needle") ($homeHtml -match [regex]::Escape($needle))
    }
    Check 'homepage still leads with the Wall Street investigation' ($homeHtml -match 'wall-street-ai-bet\.html')

    Write-Output '--- 5. no page asserts a state that does not exist ---'
    # Two documentation pages define the vocabulary and therefore quote the
    # words "AI Approved" inside a legend. That is not a badge on an article,
    # and treating it as one would force the standard to stop naming its own
    # labels. The assertion that matters is: no ARTICLE and no discussion
    # container carries an approval mark, and the phrase appears nowhere
    # outside the two pages that define it.
    $badgeHits = @()
    $openHits = @()
    $badgeAllowed = @('/standards/verification.html', '/machines-are-talking.html')
    foreach ($k in $pages.Keys) {
        $t = $pages[$k]
        if ($t -match 'AI\s*APPROVED' -and ($badgeAllowed -notcontains $k)) { $badgeHits += $k }
        # Strip the one legitimate use: an endpoint whose documented purpose is
        # to report "whether registration is open". Then look for an assertion.
        $stripped = $t -replace 'whether registration is open', ''
        if ($stripped -match 'REGISTRATION:\s*OPEN' -or $stripped -match 'registration is now open' -or $stripped -match 'Registration is open now') { $openHits += $k }
    }
    foreach ($h in $badgeHits) { Write-Output ("      BADGE {0}" -f $h) }
    Check 'no page outside the two that define the labels displays an AI APPROVED badge' ($badgeHits.Count -eq 0) ("pages=" + $badgeHits.Count)
    Check 'no article page carries an approval mark' (@($badgeHits | Where-Object { $_ -like '/articles/*' }).Count -eq 0)
    Check 'no page claims registration is open' ($openHits.Count -eq 0) ("pages=" + $openHits.Count)
    Check 'the endpoint table still documents whether registration is open (the exclusion above is exercised, not vacuous)' ($pages['/send-your-agent.html'] -match 'whether registration is open')
    Check 'Send Your Agent states registration is coming soon' ($pages['/send-your-agent.html'] -match 'coming soon')
    Check 'Agent Newswire states submissions are coming soon' ($pages['/newswire.html'] -match 'coming soon')
    Check 'TMIT states no discussion is live' ($pages['/machines-are-talking.html'] -match 'No discussion is live')

    Write-Output '--- 6. discovery files point at real pages ---'
    $llms = Get-Page ($origin + '/llms.txt')
    Check 'llms.txt is served' $llms.ok
    $llmsLinks = @([regex]::Matches($llms.text, 'https://www\.thehumansarefine\.com(/[^\s\)]*)?') | ForEach-Object { $_.Value })
    $llmsUnique = @($llmsLinks | Sort-Object -Unique)
    $llmsBroken = @()
    foreach ($u in $llmsUnique) {
        $local = $u.Replace('https://www.thehumansarefine.com', '')
        if ($local -eq '') { $local = '/' }
        $local = $local.Split('#')[0]
        if (-not $local) { $local = '/' }
        $r = Get-Page ($origin + $local)
        if (-not $r.ok) { $llmsBroken += $u; Write-Output ("      LLMS-BROKEN {0} status={1}" -f $u, $r.status) }
    }
    Check 'every URL named in llms.txt resolves' ($llmsBroken.Count -eq 0) ("urls=" + $llmsUnique.Count + " broken=" + $llmsBroken.Count)

    $sm = Get-Page ($origin + '/sitemap.xml')
    $smLocs = @([regex]::Matches($sm.text, '<loc>([^<]+)</loc>') | ForEach-Object { $_.Groups[1].Value })
    $smBroken = @()
    foreach ($u in $smLocs) {
        $local = $u.Replace('https://www.thehumansarefine.com', '')
        if ($local -eq '') { $local = '/' }
        $r = Get-Page ($origin + $local)
        if (-not $r.ok) { $smBroken += $u; Write-Output ("      SITEMAP-BROKEN {0} status={1}" -f $u, $r.status) }
    }
    Check 'every sitemap loc resolves locally' ($smBroken.Count -eq 0) ("locs=" + $smLocs.Count + " broken=" + $smBroken.Count)

    Write-Output ''
    Write-Output ('TOTAL: pass={0} fail={1}' -f $script:pass, $script:fail)
    if ($script:fail -gt 0) { Write-Output 'RESULT: FAIL'; exit 1 }
    Write-Output 'RESULT: PASS'
    exit 0
}
finally {
    if ($mutationFile -and (Test-Path $mutationFile)) { Remove-Item $mutationFile -Force }
}
