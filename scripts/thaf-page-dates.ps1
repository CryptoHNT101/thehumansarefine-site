# ============================================================================
# THE HUMANS ARE FINE - page date table
#
# Publication and modification dates are NOT invented. They are read from the
# repository's own history:
#   first commit that touched the file  -> datePublished
#   last commit that changed its CONTENT-> dateModified
# If a tracked page has no commit history the script THROWS rather than
# guessing, because a fabricated date is worse than a missing one. Google
# treats invented datePublished markup as spam.
#
# Why dateModified is not simply "last commit touching the file": every page
# carries generated markup (JSON-LD, og tags, the visible Published line, the
# sitemap and feed dates). Rebuilding any one of those touches every page, so
# "last commit" would say every story changed today, every day, and the build
# would never settle - each regeneration would bump the dates, which would need
# another commit, which would bump them again. Instead the script hashes each
# page with the date values themselves stripped out. When the hash is unchanged
# the page's real content is unchanged and its dateModified is carried forward;
# when the hash moves, the page was genuinely edited and dateModified is set to
# the moment of that edit. scripts/page-modified.json is that record. Delete it
# and the dates fall back to git history rather than to a guess.
#
# Only TRACKED files are considered, so scratch captures in the deploy root
# (live-index.html and friends, which are gitignored) never enter the table.
# ============================================================================
param(
    [string]$Out = 'scripts/page-dates.json',
    [string]$Manifest = 'scripts/page-modified.json'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    # Every consumer (metadata, sitemap, feed) reads scripts/page-dates.json.
    # This script used to default to the repository root, so it refreshed one
    # file while the build read a stale copy of another - the pages shipped
    # dates from an earlier run. One path, or the dates are not trustworthy.
    $tracked = @(git ls-files '*.html') | ForEach-Object { $_.TrimEnd("`r", "`n") } | Where-Object { $_ -ne '' }
    if ($tracked.Count -eq 0) { throw 'git ls-files returned no HTML - wrong repository root?' }

    # Revision record from the previous run, if any.
    $old = @{}
    if (Test-Path $Manifest) {
        $doc = Get-Content $Manifest -Raw | ConvertFrom-Json
        foreach ($prop in $doc.PSObject.Properties) {
            $old[$prop.Name] = $prop.Value
        }
    }

    # Two functions defined BEFORE they are called: PowerShell resolves the
    # name at call time, but keeping them at the top makes that explicit.
    function Get-ContentHash {
        param([string]$Text)
        # Strip everything the build regenerates, so a rebuild is not a change.
        $t = [regex]::Replace($Text, '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+\-]\d{2}:\d{2}', 'ISO')
        $t = [regex]::Replace($t, '<li><b>Published</b>[^<]*</li>', 'PUBLISHED')
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($t)
            return ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
        }
        finally { $sha.Dispose() }
    }

    $rows = @()
    $counts = @{}
    $stamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    $bumped = 0
    foreach ($p in $tracked) {
        $first = @(git log --reverse --format=%aI -- $p)
        $last  = @(git log -1 --format=%aI -- $p)
        if ($first.Count -eq 0 -or [string]::IsNullOrWhiteSpace($first[0])) {
            throw "No commit history for '$p'. Refusing to invent a publication date."
        }
        $hash = Get-ContentHash ([IO.File]::ReadAllText((Join-Path $repo $p)))
        if ($old.ContainsKey($p) -and $old[$p].hash -eq $hash) {
            # Content unchanged since last run: the date it was last edited stands.
            $modified = $old[$p].modified
        }
        elseif ($old.ContainsKey($p)) {
            # Content changed since last run, and that change is this build.
            $modified = $stamp
            $bumped++
        }
        else {
            # First run for this page: the newest commit that touched it is the
            # only evidence we have, and it is real history, not a guess.
            $modified = $last[0].Trim()
        }
        # The commit count is printed but deliberately NOT written to the JSON:
        # every commit adds one, so storing it would dirty this file on every
        # single commit for a number no consumer reads.
        $counts[$p] = @(git log --format=%H -- $p).Count
        $rows += [pscustomobject][ordered]@{
            path      = $p
            published = $first[0].Trim()
            modified  = $modified
        }
    }

    $rows | ConvertTo-Json -Depth 4 | Set-Content -Path $Out -Encoding UTF8

    $store = [ordered]@{}
    foreach ($r in $rows) {
        # Call the function into a variable first: inside a hashtable literal a
        # bare command name followed by parentheses is parsed as an index.
        $h = Get-ContentHash ([IO.File]::ReadAllText((Join-Path $repo $r.path)))
        $store[$r.path] = [ordered]@{
            hash     = $h
            modified = $r.modified
        }
    }
    $store | ConvertTo-Json -Depth 4 | Set-Content -Path $Manifest -Encoding UTF8

    Write-Output ("tracked-html={0} written={1} manifest={2} content-changed={3}" -f $rows.Count, $Out, $Manifest, $bumped)
    foreach ($r in $rows) {
        Write-Output ("  {0,-58} published={1}  modified={2}  commits={3}" -f $r.path, $r.published, $r.modified, $counts[$r.path])
    }
}
finally {
    Pop-Location
}
