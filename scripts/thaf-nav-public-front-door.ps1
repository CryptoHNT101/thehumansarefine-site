# ============================================================================
# THE HUMANS ARE FINE - public front door navigation
#
# Replaces the inline primary navigation on every page with one set of
# destinations that actually exist, and removes the topic anchors from the
# primary bar (they remain in the footer's BROWSE BY TOPIC row and on the
# topic pages themselves, so nothing becomes unreachable).
#
# Why a script and not 43 hand edits:
#   - the nav is duplicated inline in every page, so a hand edit is 43 chances
#     to introduce a typo in a relative path, and a typo in a nav is a 404;
#   - the relative prefix differs by depth ('' at the root, '../' one level
#     down), which is exactly the thing a human gets wrong on page 30.
#
# Analytics are preserved, not rewritten: if a page's existing Comic or Store
# link carried a data-thaf-event attribute, that attribute is carried over to
# the same link in the new bar. Pages that did not have it do not gain it,
# because adding an event to 40 pages would silently change the GA4 funnel
# that the previous tagging was built to measure.
#
#   pwsh -File scripts/thaf-nav-public-front-door.ps1 -DryRun
#   pwsh -File scripts/thaf-nav-public-front-door.ps1 -Apply
# ============================================================================
param(
    [switch]$DryRun,
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'
if (-not $DryRun -and -not $Apply) { throw 'Pass -DryRun to inspect or -Apply to write. Refusing to guess.' }

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    $files = @(Get-ChildItem -Path $repo -Filter *.html -Recurse -File |
        Where-Object { $_.FullName -notmatch '\\shots\\' })

    $results = @()
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($repo.Length + 1).Replace('\', '/')
        $depth = ($rel.ToCharArray() | Where-Object { $_ -eq '/' }).Count
        $prefix = '../' * $depth
        $html = [System.IO.File]::ReadAllText($f.FullName)

        # Anchor strictly to the primary nav. Any page whose nav is not in this
        # exact form is reported, not silently skipped.
        $m = [regex]::Match($html, '<nav class="nav wrap" aria-label="Primary navigation">.*?</nav>')
        $insert = $false
        if (-not $m.Success) {
            # Evidence Files use a reduced masthead: brand link and an
            # article-foot nav, no primary bar. They load styles.css, so the
            # same nav element renders correctly. Insert it inside the existing
            # masthead rather than restyling the page - the annex keeps its
            # reduced footer and its article-foot links, and gains the same
            # routes as every other page.
            $hm = [regex]::Match($html, '(?s)<header class="masthead">.*?</header>')
            if (-not $hm.Success) {
                $results += [pscustomobject]@{ file = $rel; status = 'NO-NAV-FOUND'; bytes = 0 }
                continue
            }
            $insert = $true
            $old = $hm.Value
        } else {
            $old = $m.Value
        }

        $comicEvent = ''
        $storeEvent = ''
        $em = [regex]::Match($old, 'data-thaf-event="(nav_comic_to_homepage)"')
        if ($em.Success) { $comicEvent = ' data-thaf-event="' + $em.Groups[1].Value + '"' }
        $em2 = [regex]::Match($old, 'data-thaf-event="(nav_store_to_homepage)"')
        if ($em2.Success) { $storeEvent = ' data-thaf-event="' + $em2.Groups[1].Value + '"' }

        $new = '<nav class="nav wrap" aria-label="Primary navigation">' +
            '<a href="' + $prefix + 'index.html">Home</a>' +
            '<a href="' + $prefix + 'news/index.html">News</a>' +
            '<a href="' + $prefix + 'disclosure-watch/index.html">Disclosure Watch</a>' +
            '<a href="' + $prefix + 'machines-are-talking.html">The Machines Are Talking</a>' +
            '<a href="' + $prefix + 'newswire.html">Agent Newswire</a>' +
            '<a href="' + $prefix + 'send-your-agent.html">Send Your Agent</a>' +
            '<a href="' + $prefix + 'standards/verification.html">The Verification Standard</a>' +
            '<a href="' + $prefix + 'index.html#comic"' + $comicEvent + '>Comic</a>' +
            '<a href="' + $prefix + 'index.html#store"' + $storeEvent + '>Store</a>' +
            '</nav>'

        if ($insert) {
            $replacement = $old.Substring(0, $old.LastIndexOf('</header>')) + $new + '</header>'
            $status = 'NAV-INSERTED'
        } else {
            if ($new -ceq $old) {
                $results += [pscustomobject]@{ file = $rel; status = 'ALREADY-CURRENT'; bytes = 0 }
                continue
            }
            $replacement = $new
            $status = 'UPDATED'
        }
        if ($Apply) {
            [System.IO.File]::WriteAllText($f.FullName, $html.Replace($old, $replacement), (New-Object System.Text.UTF8Encoding($false)))
        }
        $results += [pscustomobject]@{ file = $rel; status = $status; bytes = ($replacement.Length - $old.Length) }
    }

    $counts = $results | Group-Object status | Sort-Object Name
    Write-Output ('mode      : ' + $(if ($Apply) { 'APPLY' } else { 'DRY RUN' }))
    Write-Output ('html files: ' + $files.Count)
    foreach ($c in $counts) { Write-Output ('  {0,-16} {1}' -f $c.Name, $c.Count) }
    $bad = @($results | Where-Object { $_.status -eq 'NO-NAV-FOUND' })
    if ($bad.Count -gt 0) {
        Write-Output ''
        Write-Output 'PAGES WITH NO MATCHING PRIMARY NAV (reported, not modified):'
        foreach ($b in $bad) { Write-Output ('  ' + $b.file) }
    }
    Write-Output ''
    Write-Output ('nav items per page: 9')
} finally { Pop-Location }
