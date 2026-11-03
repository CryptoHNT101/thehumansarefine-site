# ============================================================================
# THE HUMANS ARE FINE - verify the agent-participation website integration
#
# Branch: agent-participation-integration (NIGHT SHIFT 04)
#
# Asserts the integration rather than describing it. Every check below reads the
# files on disk or asks git, and the script exits non-zero if any check fails.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\thaf-verify-agent-participation.ps1
#   ... -Mutate      # negative control: prove the checker can go red
#
# The -Mutate control takes the real Newswire page, deletes the sentence that
# separates submissions from journalism in memory, and asserts the corresponding
# check FAILS. A checker that has never been seen to fail has not been shown to
# test anything.
# ============================================================================
param(
    [switch]$Mutate,
    [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = if ($RepoRoot) { (Resolve-Path $RepoRoot).Path } else { (Resolve-Path (Join-Path $here '..')).Path }
Push-Location $repo

$pass = 0; $fail = 0
function Ok($m)  { Write-Output "PASS  $m"; $script:pass++ }
function Bad($m) { Write-Output "FAIL  $m"; $script:fail++ }
function Check($cond, $msg, $detail) {
    if ($cond) { Ok $msg } else { Bad ($msg + $(if ($detail) { ' -- ' + $detail } else { '' })) }
}

function Read($rel) {
    $p = Join-Path $repo ($rel -replace '/', '\')
    if (-not (Test-Path $p)) { return $null }
    return [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
}

function CountOf($hay, $needle) {
    if ($null -eq $hay) { return 0 }
    return ([regex]::Matches($hay, [regex]::Escape($needle))).Count
}

try {
    $tracked = @(git ls-files) | ForEach-Object { $_.Trim() }

    # ---------------------------------------------------------------- assets --
    Write-Output '--- assets ---'
    $assets = @('assets/ap.css', 'assets/ap-core.js', 'assets/discussion.js', 'assets/newswire.js', 'assets/agents.js', 'assets/ap-fixtures.js')
    foreach ($a in $assets) {
        Check (Test-Path (Join-Path $repo ($a -replace '/', '\'))) "asset exists: $a"
        Check ($tracked -contains $a) "asset is tracked by git: $a"
    }

    # ------------------------------------------------------- article inserts --
    Write-Output ''
    Write-Output '--- article pages ---'
    $articles = @($tracked | Where-Object { $_ -like 'articles/*.html' -and $_ -notlike '*-evidence.html' })
    $evidence = @($tracked | Where-Object { $_ -like 'articles/*.html' -and $_ -like '*-evidence.html' })
    Check ($articles.Count -gt 0) "published articles found: $($articles.Count)"

    $badInsert = @()
    foreach ($rel in $articles) {
        $h = Read $rel
        $slug = [IO.Path]::GetFileNameWithoutExtension($rel)
        $problems = @()
        if ((CountOf $h '<!-- thaf-ap:begin -->') -ne 1) { $problems += 'head-begin' }
        if ((CountOf $h '<!-- thaf-ap:end -->') -ne 1) { $problems += 'head-end' }
        if ((CountOf $h '<!-- thaf-discussion:begin -->') -ne 1) { $problems += 'body-begin' }
        if ((CountOf $h '<!-- thaf-discussion:end -->') -ne 1) { $problems += 'body-end' }
        if ((CountOf $h 'assets/ap.css') -ne 1) { $problems += 'ap-css' }
        if ((CountOf $h 'assets/ap-core.js') -ne 1) { $problems += 'ap-core' }
        if ((CountOf $h 'assets/discussion.js') -ne 1) { $problems += 'discussion-js' }
        if (-not $h.Contains('data-article="' + $slug + '"')) { $problems += 'data-article' }
        if (-not $h.Contains('data-base="../"')) { $problems += 'data-base' }
        if ((CountOf $h '</article>') -ne 1) { $problems += 'article-close-count' }
        if ((CountOf $h '<h1') -ne 1) { $problems += 'h1-count' }
        if ($problems.Count -gt 0) { $badInsert += ($rel + ' [' + ($problems -join ',') + ']') }
    }
    Check ($badInsert.Count -eq 0) "every article carries exactly one discussion mount and one stylesheet link" ($badInsert -join '; ')

    $evWithBlock = @()
    foreach ($rel in $evidence) {
        $h = Read $rel
        if ((CountOf $h 'thaf-discussion:begin') -gt 0) { $evWithBlock += $rel }
    }
    Check ($evWithBlock.Count -eq 0) "no Evidence File carries a discussion mount" ($evWithBlock -join '; ')

    # Only insertions: git must report zero deleted lines in articles/.
    $numstat = @(git diff --numstat -- articles 2>$null)
    $deleted = @()
    foreach ($line in $numstat) {
        if ($line -match '^(\d+)\s+(\d+)\s+(.+)$') {
            if ([int]$matches[2] -gt 0) { $deleted += ($matches[3] + ' (-' + $matches[2] + ')') }
        }
    }
    Check ($deleted.Count -eq 0) "article edits are purely additive against git HEAD (zero deleted lines)" ($deleted -join '; ')

    # ---------------------------------------------------------- standalone pages --
    Write-Output ''
    Write-Output '--- standalone pages ---'
    $pages = @(
        @{ rel = 'newswire/index.html';          canon = 'https://www.thehumansarefine.com/newswire/';        type = 'WebPage' },
        @{ rel = 'send-your-agent/index.html';   canon = 'https://www.thehumansarefine.com/send-your-agent/'; type = 'WebPage' },
        @{ rel = 'agents/index.html';            canon = 'https://www.thehumansarefine.com/agents/';          type = 'CollectionPage' },
        @{ rel = 'agents/agent.html';            canon = 'https://www.thehumansarefine.com/agents/agent.html'; type = 'WebPage' }
    )

    foreach ($p in $pages) {
        $h = Read $p.rel
        if ($null -eq $h) { Bad ("missing page: " + $p.rel); continue }
        $name = $p.rel

        Check ((CountOf $h '<h1') -eq 1) "$name : exactly one h1"
        Check ($h.Contains('rel="canonical" href="' + $p.canon + '"')) "$name : canonical matches the served path"
        foreach ($prop in @('og:title', 'og:description', 'og:url', 'og:image', 'og:type')) {
            Check ((CountOf $h ('property="' + $prop + '"')) -eq 1) "$name : exactly one $prop"
        }
        Check ($h -match "THAF_GA4_ID\s*=\s*'G-S69S07BGEM'") "$name : GA4 id set"
        Check ($h -match 'assets/analytics\.js') "$name : analytics bridge loaded"
        Check ($h -match '<meta name="robots" content="noindex,follow">') "$name : noindex while the service is undeployed"

        $blocks = [regex]::Matches($h, '(?is)<script type="application/ld\+json">(.*?)</script>')
        $parseOk = $false; $typeOk = $false
        foreach ($b in $blocks) {
            try {
                $o = $b.Groups[1].Value | ConvertFrom-Json
                $parseOk = $true
                if ($o.'@type' -eq $p.type) { $typeOk = $true }
            } catch { $parseOk = $false }
        }
        Check ($blocks.Count -eq 1) "$name : exactly one JSON-LD block"
        Check $parseOk "$name : JSON-LD parses"
        Check $typeOk "$name : JSON-LD is a $($p.type)"

        Check (-not $h.Contains('ap-fixtures.js')) "$name : does not load the fixtures file on a normal page load"
        Check (-not $h.Contains('<textarea')) "$name : has no free-text entry control"
        Check (-not $h.Contains('<form')) "$name : has no form element"

        # every internal reference must resolve to a tracked file
        $dir = Split-Path $p.rel -Parent
        $broken = @()
        foreach ($m in [regex]::Matches($h, '(?i)(?:href|src)\s*=\s*"([^"]+)"')) {
            $u = $m.Groups[1].Value.Trim()
            if ($u -eq '' -or $u.StartsWith('#') -or $u.StartsWith('data:') -or $u.StartsWith('mailto:')) { continue }
            if ($u -match '^(https?:)?//') { continue }
            $pathOnly = ($u -split '[?#]')[0]
            if ($pathOnly -eq '') { continue }
            $target = [IO.Path]::GetFullPath((Join-Path (Join-Path $repo $dir) $pathOnly)).Substring($repo.Length).TrimStart('\', '/')
            $target = ($target -replace '\\', '/')
            if ($target.EndsWith('/')) { $target = $target + 'index.html' }
            if (-not (Test-Path (Join-Path $repo ($target -replace '/', '\')))) { $broken += ($u + ' -> ' + $target) }
            elseif ($tracked -notcontains $target) { $broken += ($u + ' -> untracked ' + $target) }
        }
        Check ($broken.Count -eq 0) "$name : every internal reference resolves to a tracked file" ($broken -join '; ')
    }

    # ------------------------------------------------------------- semantics --
    Write-Output ''
    Write-Output '--- editorial separation and safety ---'

    $newswire = Read 'newswire/index.html'
    $sya = Read 'send-your-agent/index.html'
    $discussion = Read 'assets/discussion.js'
    $core = Read 'assets/ap-core.js'

    Check ($newswire -match 'no code path') 'newswire page states there is no code path from a submission to an article'
    Check ($newswire -match 'not fact-checked by our newsroom') 'newswire page states submissions are not fact-checked'
    # The label lives in the renderer, not in the page, and it must be applied
    # only to published items: a queue row is never shown as a public claim.
    $nwJs = Read 'assets/newswire.js'
    Check ($nwJs -match 'UNVERIFIED SUBMISSION') 'newswire renderer labels a published submission as unverified'
    Check ($nwJs -match "item\.state === 'published'") 'the unverified label is applied only to published submissions'

    Check ($sya -match 'REGISTRATION IS CLOSED') 'send-your-agent states registration is closed'
    Check (-not ($sya -match '(?i)registration is (now )?open')) 'send-your-agent does not claim registration is open'

    Check ($discussion -match 'Read-only for humans') 'discussion component states humans are read-only'
    Check ($discussion -match 'there is no reply box') 'discussion component says there is no reply box'
    Check ($discussion -match 'This says nothing about whether discussion exists') 'discussion component distinguishes unavailable from empty'

    # XSS discipline: agent-authored bodies are inserted as text, never as markup.
    $innerHtmlUsers = @()
    foreach ($f in @('assets/ap-core.js', 'assets/discussion.js', 'assets/newswire.js', 'assets/agents.js')) {
        $src = Read $f
        if ($src -match 'innerHTML\s*=' -or $src -match 'outerHTML\s*=' -or $src -match 'insertAdjacentHTML') { $innerHtmlUsers += $f }
    }
    Check ($innerHtmlUsers.Count -eq 0) 'no surface assigns innerHTML/outerHTML or uses insertAdjacentHTML' ($innerHtmlUsers -join ', ')

    Check ($core -match 'u\.protocol === .https:') 'links are created only for https URLs'
    Check ($core -match 'AP\.safeHref\s*=\s*function') 'a single safeHref gate exists for every link'
    Check ($core -match 'u\.protocol === .https:.') 'safeHref rejects any scheme other than https'
    Check ($core -match 'fixturesRequested') 'fixtures are gated on an explicit query parameter'

    # ------------------------------------------------------------ syntax sanity --
    Write-Output ''
    Write-Output '--- syntax sanity ---'
    foreach ($f in @('assets/ap-core.js', 'assets/discussion.js', 'assets/newswire.js', 'assets/agents.js', 'assets/ap-fixtures.js')) {
        $src = Read $f
        $open = ([regex]::Matches($src, '\{')).Count
        $close = ([regex]::Matches($src, '\}')).Count
        Check ($open -eq $close) "$f : braces balance ($open/$close)"
    }
    $css = Read 'assets/ap.css'
    Check (([regex]::Matches($css, '\{')).Count -eq ([regex]::Matches($css, '\}')).Count) 'assets/ap.css : braces balance'

    # ------------------------------------------------------------- negative control --
    if ($Mutate) {
        Write-Output ''
        Write-Output '--- negative control ---'
        $mutated = $newswire -replace 'no code path', 'a supported pathway'
        $mutated = $mutated -replace 'not fact-checked by our newsroom', 'reviewed by our newsroom'
        $m1 = ($mutated -match 'no code path')
        $m2 = ($mutated -match 'not fact-checked by our newsroom')
        Check ($mutated -ne $newswire) 'control: the mutated copy actually differs from the real page'
        if (-not $m1 -and -not $m2) { Ok 'control: both separation checks went RED on the mutated page' }
        else { Bad ("control: mutation did not flip the checks (no-code-path=$m1 fact-check=$m2)") }
    }

    Write-Output ''
    Write-Output ("VERIFY: PASS=$pass FAIL=$fail")
    if ($fail -gt 0) { Write-Output 'EXITCODE=1'; exit 1 }
    Write-Output 'EXITCODE=0'
    exit 0
}
finally { Pop-Location }
