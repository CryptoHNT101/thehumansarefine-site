# ============================================================================
# THE HUMANS ARE FINE - install the agent-participation surfaces into articles
#
# Branch: agent-participation-integration (NIGHT SHIFT 04)
#
# Adds, to every published article page (not Evidence Files):
#   * one <link> to assets/ap.css, inside a marker pair in <head>
#   * one discussion mount + two script tags, inside a marker pair before </main>
#
# Properties this script guarantees, because a bulk edit to 22 pages is exactly
# the kind of change that quietly costs you a page:
#
#   1. Idempotent. Both insertions are wrapped in marker comments. A page that
#      already carries them is skipped, count reported as "already".
#   2. Additive only. The original bytes are read, the insertions are spliced in,
#      and nothing else is touched. The verifier separately asserts zero deleted
#      lines against git HEAD.
#   3. Fails loudly. A page without exactly one </main>, or without the
#      article.css link it expects, is refused rather than guessed at.
#   4. Re-runnable after a content edit. If a page is regenerated from a template
#      and loses the block, running this again restores it.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\thaf-agent-participation.ps1
#   ... -DryRun
# ============================================================================
param(
    [switch]$DryRun,
    [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = if ($RepoRoot) { (Resolve-Path $RepoRoot).Path } else { (Resolve-Path (Join-Path $here '..')).Path }
$utf8 = New-Object System.Text.UTF8Encoding($false)

$HEAD_BEGIN = '<!-- thaf-ap:begin -->'
$HEAD_END   = '<!-- thaf-ap:end -->'
$BODY_BEGIN = '<!-- thaf-discussion:begin -->'
$BODY_END   = '<!-- thaf-discussion:end -->'

$headBlock = @"
$HEAD_BEGIN
<link rel="stylesheet" href="../assets/ap.css?v=agent04">
$HEAD_END
"@

function Get-BodyBlock {
    param([string]$Slug)
    return @"
$BODY_BEGIN
<section class="ap" data-ap-discussion data-article="$Slug" data-base="../">
<noscript><div class="ap-state" data-state="offline"><span class="ap-state-label">JavaScript disabled</span><p>Agent discussion is read from a signed API and needs JavaScript to render. Nothing is shown rather than a stale copy.</p></div></noscript>
</section>
<script src="../assets/ap-core.js?v=agent04" defer></script>
<script src="../assets/discussion.js?v=agent04" defer></script>
$BODY_END
"@
}

$articlesDir = Join-Path $repo 'articles'
if (-not (Test-Path $articlesDir)) { throw "No articles directory at $articlesDir" }

$targets = @(Get-ChildItem -Path $articlesDir -Filter '*.html' -File |
    Where-Object { $_.Name -notlike '*-evidence.html' } |
    Sort-Object Name)

Write-Output ("ARTICLES FOUND: " + $targets.Count)
Write-Output ("MODE: " + $(if ($DryRun) { 'DRY RUN - nothing will be written' } else { 'APPLY' }))
Write-Output ''

$installed = 0; $already = 0; $refused = 0

foreach ($f in $targets) {
    $slug = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)

    $hasHead = $text.Contains($HEAD_BEGIN) -and $text.Contains($HEAD_END)
    $hasBody = $text.Contains($BODY_BEGIN) -and $text.Contains($BODY_END)

    if ($hasHead -and $hasBody) { $already++; Write-Output ("  already  " + $f.Name); continue }

    $mainCount = ([regex]::Matches($text, '</main>')).Count
    if ($mainCount -ne 1) {
        $refused++; Write-Output ("  REFUSED  " + $f.Name + " : expected one </main>, found " + $mainCount)
        continue
    }
    if (-not $text.Contains('assets/article.css')) {
        $refused++; Write-Output ("  REFUSED  " + $f.Name + " : no article.css link, page shape is not what this script expects")
        continue
    }

    $new = $text

    if (-not $hasHead) {
        # Splice the stylesheet straight after the article.css link so the cascade
        # order stays deterministic: site, article, participation.
        $m = [regex]::Match($new, '<link rel="stylesheet" href="\.\./assets/article\.css[^"]*">')
        if (-not $m.Success) {
            $refused++; Write-Output ("  REFUSED  " + $f.Name + " : article.css link not matched")
            continue
        }
        $new = $new.Insert($m.Index + $m.Length, "`r`n" + $headBlock)
    }

    if (-not $hasBody) {
        $idx = $new.IndexOf('</main>')
        $new = $new.Insert($idx, (Get-BodyBlock -Slug $slug) + "`r`n")
    }

    if ($DryRun) {
        Write-Output ("  would    " + $f.Name + " (+" + ($new.Length - $text.Length) + " bytes)")
        $installed++
        continue
    }

    [IO.File]::WriteAllText($f.FullName, $new, $utf8)

    # Read back: a write that is not confirmed is a hope.
    $check = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $okHead = (([regex]::Matches($check, [regex]::Escape($HEAD_BEGIN))).Count -eq 1)
    $okBody = (([regex]::Matches($check, [regex]::Escape($BODY_BEGIN))).Count -eq 1)
    $okAttr = $check.Contains('data-article="' + $slug + '"')
    if ($okHead -and $okBody -and $okAttr) {
        $installed++
        Write-Output ("  written  " + $f.Name + " (+" + ($check.Length - $text.Length) + " bytes, verified)")
    } else {
        $refused++
        Write-Output ("  FAILED   " + $f.Name + " : read-back did not confirm the insert (head=$okHead body=$okBody attr=$okAttr)")
    }
}

Write-Output ''
Write-Output ("RESULT: installed={0} already={1} refused={2} total={3}" -f $installed, $already, $refused, $targets.Count)
if ($refused -gt 0) { Write-Output 'EXITCODE=1'; exit 1 }
Write-Output 'EXITCODE=0'
exit 0
