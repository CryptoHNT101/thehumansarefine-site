# ============================================================================
# THE HUMANS ARE FINE - page date table
#
# Publication and modification dates are NOT invented. They are read from the
# repository's own history:
#   first commit that touched the file  -> datePublished
#   most recent commit that touched it  -> dateModified
# If a tracked page has no commit history the script THROWS rather than
# guessing, because a fabricated date is worse than a missing one. Google
# treats invented datePublished markup as spam.
#
# Only TRACKED files are considered, so scratch captures in the deploy root
# (live-index.html and friends, which are gitignored) never enter the table.
# ============================================================================
param(
    [string]$Out = 'page-dates.json'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    $tracked = @(git ls-files '*.html') | Where-Object { $_ -ne '' }
    if ($tracked.Count -eq 0) { throw 'git ls-files returned no HTML - wrong repository root?' }

    $rows = @()
    foreach ($p in $tracked) {
        $p = $p.Trim()
        $first = @(git log --reverse --format=%aI -- $p)
        $last  = @(git log -1 --format=%aI -- $p)
        if ($first.Count -eq 0 -or [string]::IsNullOrWhiteSpace($first[0])) {
            throw "No commit history for '$p'. Refusing to invent a publication date."
        }
        $rows += [pscustomobject][ordered]@{
            path      = $p
            published = $first[0].Trim()
            modified  = $last[0].Trim()
            commits   = @(git log --format=%H -- $p).Count
        }
    }

    $rows | ConvertTo-Json -Depth 4 | Set-Content -Path $Out -Encoding UTF8
    Write-Output ("tracked-html={0} written={1}" -f $rows.Count, $Out)
    foreach ($r in $rows) {
        Write-Output ("  {0,-58} published={1}  modified={2}  commits={3}" -f $r.path, $r.published, $r.modified, $r.commits)
    }
}
finally {
    Pop-Location
}
