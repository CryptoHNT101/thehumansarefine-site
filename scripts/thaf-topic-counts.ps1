# ============================================================================
# THE HUMANS ARE FINE - keep topic-archive counts and descriptions honest
#
# Two topic archives shipped with a description that did not state how many
# stories they held ("... published stories", number missing), and one archive
# advertised itself in the sitemap while linking no story at all. A meta
# description that misstates the page is worse than a plain one.
#
# This script counts the story cards that are actually on each archive page and
# writes that number into the description. It cannot change how many stories
# exist, and it refuses to invent one when the page holds none.
# ============================================================================
param([switch]$WhatIf)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    function Decode([string]$s) {
        if ($null -eq $s) { return '' }
        $s = $s -replace '&mdash;', [char]0x2014
        $s = $s -replace '&amp;', '&'
        $s = $s -replace '&quot;', '"'
        $s = $s -replace '&#39;', "'"
        return $s.Trim()
    }

    $empty = @()
    foreach ($rel in @(git ls-files 'topics/*.html' | Sort-Object)) {
        $full = Join-Path $repo $rel
        $html = [IO.File]::ReadAllText($full)
        $original = $html

        $cards = [regex]::Matches($html, '(?is)<article class="story-card">')
        $n = $cards.Count

        $hm = [regex]::Match($html, '(?is)<h1[^>]*>(.*?)</h1>')
        if (-not $hm.Success) { throw "no h1 in $rel - cannot name the archive." }
        $name = Decode ($hm.Groups[1].Value -replace '<[^>]+>', '')

        # every card must point at a story that exists, or the count is a lie
        foreach ($m in [regex]::Matches($html, '(?is)<h3><a href="\.\./(articles/[a-z0-9\-]+\.html)"')) {
            $target = $m.Groups[1].Value
            if (-not (Test-Path (Join-Path $repo $target))) { throw "$rel links $target which does not exist." }
        }

        if ($n -eq 0) {
            $empty += $rel
            $desc = "No story has yet been filed under $name. Archive entries appear here when one is."
        } elseif ($n -eq 1) {
            $desc = "1 published story from The Humans Are Fine filed under $name."
        } else {
            $desc = "$n published stories from The Humans Are Fine filed under $name."
        }

        $mm = [regex]::Match($html, '(?is)<meta name="description" content="(.*?)">')
        if (-not $mm.Success) { throw "no meta description in $rel" }
        $old = $mm.Groups[1].Value
        if ($old -ne $desc) {
            $html = $html.Remove($mm.Groups[1].Index, $mm.Groups[1].Length).Insert($mm.Groups[1].Index, [System.Security.SecurityElement]::Escape($desc))
            Write-Output ("  {0}: {1} card(s)" -f $rel, $n)
            Write-Output ("     was: $old")
            Write-Output ("     now: $desc")
            if (-not $WhatIf) { [IO.File]::WriteAllText($full, $html, (New-Object System.Text.UTF8Encoding($false))) }
        } else {
            Write-Output ("  ok  {0}: {1} card(s), description already correct" -f $rel, $n)
        }

        # the on-page count line must agree with the cards
        $line = [regex]::Match($html, '(?is)<p class="kicker">(\d+) published stories? under this heading\.</p>')
        if ($n -gt 0 -and $line.Success -and [int]$line.Groups[1].Value -ne $n) {
            Write-Output ("  WARN {0}: on-page heading says {1}, page holds {2} cards" -f $rel, $line.Groups[1].Value, $n)
        }
    }
    if ($empty.Count) {
        Write-Output ('EMPTY ARCHIVES (must be filled or de-listed before publication): ' + ($empty -join ', '))
    }
}
finally { Pop-Location }
