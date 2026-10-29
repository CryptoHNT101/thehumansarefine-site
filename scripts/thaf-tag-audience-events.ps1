# ============================================================================
# THE HUMANS ARE FINE - tag the links the audience report actually needs
#
# The site could already tell you a page had been viewed. It could not tell you
# whether anybody opened the Evidence File, went back to the story, stepped up
# to the topic archive, or read the corrections policy - the four things that
# separate a reader from a bounce. assets/analytics.js turns any
# data-thaf-event attribute into a named GA4 event; this script attaches them.
#
# Only links whose destination is already on the page are tagged. No event, and
# no parameter, is added that analytics.js does not implement.
# Idempotent: an attribute already present is left alone.
# ============================================================================
param([switch]$WhatIf)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    $total = @{}
    foreach ($rel in @(git ls-files 'articles/*.html' | Sort-Object)) {
        $full = Join-Path $repo $rel
        $html = [IO.File]::ReadAllText($full)
        $original = $html
        $script:__hits = 0

        # story -> its Evidence File, wherever the link appears
        $html = [regex]::Replace($html, '(?is)<a (?![^>]*data-thaf-event)[^>]*href="[a-z0-9\-]+-evidence\.html"[^>]*>', {
                param($m)
                $script:__hits++
                return ($m.Value -replace '^<a ', '<a data-thaf-event="evidence_file_open" ')
            })

        # Evidence File -> the story it supports (the "Article" row of its meta list)
        $html = [regex]::Replace($html, '(?is)(<li><b>Article</b>\s*)(<a )(?![^>]*data-thaf-event)', {
                param($m)
                $script:__hits++
                return ($m.Groups[1].Value + '<a data-thaf-event="back_to_article" ')
            })

        # breadcrumb step up to the topic archive
        $html = [regex]::Replace($html, '(?is)<a (?![^>]*data-thaf-event)href="\.\./topics/[a-z0-9\-]+\.html"', {
                param($m)
                $script:__hits++
                return ($m.Value -replace '^<a ', '<a data-thaf-event="topic_archive_open" ')
            })

        # the corrections route out of an article
        $html = [regex]::Replace($html, '(?is)<a (?![^>]*data-thaf-event)href="\.\./standards/index\.html"', {
                param($m)
                $script:__hits++
                return ($m.Value -replace '^<a ', '<a data-thaf-event="corrections_open" ')
            })

        if ($html -ne $original) {
            if (-not $WhatIf) { [IO.File]::WriteAllText($full, $html, (New-Object System.Text.UTF8Encoding($false))) }
            Write-Output ("  {0}: {1} link(s) tagged" -f $rel, $script:__hits)
        }
        $total[$rel] = $script:__hits
    }

    # merchants: the store link is already tagged thaf_store_click on the pages
    # that carry it; confirm rather than duplicate
    $storePages = @(git ls-files '*.html' | Where-Object { (Get-Content $_ -Raw) -match 'etsy\.com/shop' })
    Write-Output ('pages linking to the Etsy store: ' + ($storePages -join ', '))

    $sum = ($total.Values | Measure-Object -Sum).Sum
    Write-Output ("total links tagged: {0}  whatIf={1}" -f $sum, [bool]$WhatIf)
}
finally { Pop-Location }
