# ============================================================================
# THE HUMANS ARE FINE - add a visible byline to every published article
#
# WHY
#   Google's Google News policies page (support.google.com/news/publisher-center/
#   answer/6204050, read 2026-10-30) lists, under "Transparency", the four things
#   news sources on Google should provide:
#       "Clear dates and bylines" / "Information about the authors, publication,
#        and publisher" / "Information about the company or network behind the
#        content" / "Contact information"
#
#   Google Search's own AI-content guidance (developers.google.com/search/blog/
#   2023/02/google-search-and-ai-content) adds:
#       "publishers that appear in Google News should use bylines and author
#        information"
#   and, in the same FAQ:
#       "Giving AI an author byline is probably not the best way to follow our
#        recommendation to make clear to readers when AI is part of the content
#        creation process."
#
#   So the byline names the newsroom (an entity, not a fake human) and links
#   straight to the published AI-disclosure and editorial policy. The schema.org
#   author stays an Organization for the same reason.
#
# WHAT IT TOUCHES
#   1. standards/index.html : <h2>AI disclosure</h2> gains id="ai-disclosure" so
#      the byline link resolves to a real anchor instead of a dangling fragment.
#   2. articles/*.html      : a byline <li> is inserted as the first item of
#      <ul class="article-meta">. Evidence Files (-evidence.html) are excluded.
#
# SAFETY
#   Idempotent: a second run changes nothing. Refuses (exit 1) if an article has
#   no article-meta list, rather than silently skipping the file.
# ============================================================================
param(
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    $byline = '<li><b>By</b> <a href="../standards/#ai-disclosure">THE HUMANS ARE FINE newsroom agents</a>, under human editorial authority</li>'

    # ---- 1. anchor on the standards page -----------------------------------
    $stdPath = Join-Path $repo 'standards\index.html'
    $std = [System.IO.File]::ReadAllText($stdPath)
    $anchorChanged = $false
    if ($std -notmatch 'id="ai-disclosure"') {
        $needle = '<h2>AI disclosure</h2>'
        if ($std -notmatch [regex]::Escape($needle)) {
            throw "standards page has no '<h2>AI disclosure</h2>' heading - refusing to add an anchor to a heading that is not there."
        }
        if ($std -notmatch [regex]::Escape($needle)) { throw 'anchor target obsolete' }
        $std = $std.Replace($needle, '<h2 id="ai-disclosure">AI disclosure</h2>')
        $anchorChanged = $true
        if (-not $WhatIf) { [System.IO.File]::WriteAllText($stdPath, $std, (New-Object System.Text.UTF8Encoding($false))) }
        Write-Output "standards/index.html : anchor id added to 'AI disclosure' heading"
    } else {
        Write-Output "standards/index.html : anchor already present, unchanged"
    }

    # ---- 2. byline on every article ---------------------------------------
    $articles = @(Get-ChildItem (Join-Path $repo 'articles') -Filter '*.html' |
                  Where-Object { $_.Name -notlike '*-evidence.html' } | Sort-Object Name)
    if ($articles.Count -eq 0) { throw 'No article pages found under articles/.' }

    $added = 0; $skipped = 0
    foreach ($f in $articles) {
        $html = [System.IO.File]::ReadAllText($f.FullName)
        $m = [regex]::Match($html, '(?is)<ul class="article-meta">')
        if (-not $m.Success) { throw ($f.Name + ' has no <ul class="article-meta"> - refusing to skip silently.') }

        # Already carries a byline as the first metadata item?
        $firstItem = [regex]::Match($html, '(?is)<ul class="article-meta">\s*<li>(.{0,200}?)</li>')
        if ($firstItem.Success -and $firstItem.Groups[1].Value -match '<b>By</b>') {
            $skipped++
            Write-Output ("  {0} : byline already present" -f $f.Name)
            continue
        }

        $insertAt = $m.Index + $m.Length
        $new = $html.Substring(0, $insertAt) + "`r`n" + $byline + $html.Substring($insertAt)

        # verify the edit actually landed before writing
        $check = [regex]::Match($new, '(?is)<ul class="article-meta">\s*<li><b>By</b>')
        if (-not $check.Success) { throw "byline insertion failed for $($f.Name)" }

        if (-not $WhatIf) { [System.IO.File]::WriteAllText($f.FullName, $new, (New-Object System.Text.UTF8Encoding($false))) }
        $added++
        Write-Output ("  {0} : byline added" -f $f.Name)
    }

    Write-Output ''
    Write-Output ("byline added: {0}   already present: {1}   articles: {2}" -f $added, $skipped, $articles.Count)

    # ---- 3. read back from disk -------------------------------------------
    if (-not $WhatIf) {
        $bad = @()
        foreach ($f in $articles) {
            $t = [System.IO.File]::ReadAllText($f.FullName)
            if ($t -notmatch '(?is)<ul class="article-meta">\s*<li><b>By</b>') { $bad += $f.Name }
        }
        if ($bad.Count -gt 0) { throw ('byline missing after write: ' + ($bad -join ', ')) }
        $stdNow = [System.IO.File]::ReadAllText($stdPath)
        if ($stdNow -notmatch 'id="ai-disclosure"') { throw 'anchor missing after write' }
        Write-Output ("read-back: all {0} articles carry the byline; anchor resolves" -f $articles.Count)
    }
}
finally { Pop-Location }
