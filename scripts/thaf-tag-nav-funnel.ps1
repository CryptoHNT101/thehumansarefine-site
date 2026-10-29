# ============================================================================
# THE HUMANS ARE FINE - tag the Comic and Store navigation path
#
# The only measured funnel today is on the homepage (comic_read_click,
# comic_pdf_download_click, etsy_store_click). From an article, Comic and Store
# are plain links to homepage anchors, so a reader who leaves an article for the
# shop is invisible. This adds a data-thaf-event to that path on every page.
#
# Additive and idempotent: it only adds the attribute where it is absent, and
# never touches an existing data-thaf-event. Nothing is renamed or removed.
# ============================================================================
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    $pages = @(git ls-files '*.html') | ForEach-Object { $_.Trim() }
    $rules = @(
        @{ pattern = '(?<=href="[^"]*#comic")(?![^>]*data-thaf-event)([^>]*)>'; event = 'nav_comic_to_homepage' },
        @{ pattern = '(?<=href="[^>]*#store")(?![^>]*data-thaf-event)([^>]*)>'; event = 'nav_store_to_homepage' }
    )
    $changed = 0
    foreach ($rel in $pages) {
        $full = Join-Path $repo $rel
        $html = [IO.File]::ReadAllText($full)
        $before = $html
        foreach ($r in $rules) {
            $html = [regex]::Replace($html, $r.pattern, (' data-thaf-event="' + $r.event + '"$1>'))
        }
        if ($html -ne $before) {
            [IO.File]::WriteAllText($full, $html, (New-Object System.Text.UTF8Encoding($false)))
            $changed++
            Write-Output "tagged  $rel"
        }
    }
    Write-Output "pages changed this run: $changed of $($pages.Count)"
}
finally { Pop-Location }
