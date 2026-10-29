# ============================================================================
# THE HUMANS ARE FINE - make article <title> carry the story's real subject
#
# Problem this fixes: <title> was a 26-40 character fragment ("Learned to
# Invent Problems", "Deleting a Model's Cheating") that named no company,
# model or institution, while the full headline - which does name them - was
# only in og:title. A search result therefore showed the fragment, and <title>
# disagreed with og:title on 11 of 23 pages.
#
# Rule: <title> becomes the story's own <h1>. No new sentence is written. The
# headline is copy the paper already published, already displays on the page
# and already feeds og:title - so nothing here is invented, and <title> and
# og:title can no longer contradict each other.
#
# Guard: a headline longer than 110 characters (Google's documented ceiling for
# an article headline) is left with its existing short title, which is the
# editor's deliberate short name. That case is reported, not silently changed.
# ============================================================================
param([switch]$WhatIf, [int]$MaxLen = 110)
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
        $s = $s -replace '&rsquo;', [char]0x2019
        $s = $s -replace '&apos;', "'"
        return $s.Trim()
    }
    function Esc([string]$s) { return [System.Security.SecurityElement]::Escape($s) }

    $changed = 0; $same = 0
    foreach ($rel in @(git ls-files 'articles/*.html' | Sort-Object)) {
        $full = Join-Path $repo $rel
        $html = [IO.File]::ReadAllText($full)
        $original = $html

        $tm = [regex]::Match($html, '(?is)<title>(.*?)</title>')
        if (-not $tm.Success) { throw "no <title> in $rel" }
        $oldRaw = $tm.Groups[1].Value
        $old = Decode $oldRaw

        $hm = [regex]::Match($html, '(?is)<h1[^>]*>(.*?)</h1>')
        if (-not $hm.Success) {
            Write-Output ("  KEPT     $rel  (no h1 to borrow; title stays: `"$old`")")
            $same++; continue
        }
        $h1 = Decode ($hm.Groups[1].Value -replace '<[^>]+>', '')
        if (-not $h1) { Write-Output ("  KEPT     $rel  (empty h1)"); $same++; continue }

        # Some Evidence Files show an internal work-order code in the h1
        # ("Evidence File - Story B: ..."). "Story B" means nothing to a
        # searcher, so the code is dropped from the title element only - the
        # h1 on the page is left exactly as written. The remaining words are
        # still the page's own copy.
        $story = [regex]::Match($h1, '^(?i)Evidence File\s*[-\u2013\u2014]\s*Story\s+[A-Z]:\s*(.+)$')
        if ($story.Success) { $h1 = 'Evidence File: ' + $story.Groups[1].Value.Trim() }

        if ($h1.Length -gt $MaxLen) {
            Write-Output ("  KEPT     $rel  (headline is {0} chars, over the {1}-char ceiling; short title `"{2}`" retained)" -f $h1.Length, $MaxLen, $old)
            $same++; continue
        }
        if ($h1 -eq $old) { $same++; continue }

        # only touch the <title> element itself; og:title/twitter:title are
        # handled separately and already carry the headline
        $html = $html.Remove($tm.Groups[1].Index, $tm.Groups[1].Length).Insert($tm.Groups[1].Index, (Esc $h1))

        $new = ([regex]::Match($html, '(?is)<title>(.*?)</title>')).Groups[1].Value
        Write-Output ("  RETITLED $rel")
        Write-Output ("           was [{0}] {1}" -f $old.Length, $old)
        Write-Output ("           now [{0}] {1}" -f (Decode $new).Length, (Decode $new))

        if ($html -eq $original) { $same++; continue }
        if (-not $WhatIf) { [IO.File]::WriteAllText($full, $html, (New-Object System.Text.UTF8Encoding($false))) }
        $changed++
    }
    Write-Output ("titles changed={0} unchanged={1} whatIf={2}" -f $changed, $same, [bool]$WhatIf)
}
finally { Pop-Location }
