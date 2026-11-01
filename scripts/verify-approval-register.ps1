# Verifies editorial/approval-register.json against the articles on disk.
#
# Two things this proves, and one it refuses to pretend:
#   1. Every APPROVED row still matches the file on disk, so nothing approved
#      was silently edited afterwards.
#   2. Every tracked article appears in the register exactly once.
#   3. It does NOT prove the Commander approved anything. It proves the record
#      of approval is intact. Articles published before the register existed
#      are reported as unrecorded, which is a finding, not a pass.
#
# Exit 0 only when no revision has drifted and no article is missing from the
# register. Unrecorded approvals are reported as a count and a WARN.
param(
    [string]$RegisterPath = 'editorial/approval-register.json'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
$pass = 0; $fail = 0; $warn = 0
function Ok($m)   { Write-Output "PASS  $m"; $script:pass++ }
$__sha = [System.Security.Cryptography.SHA256]::Create()
function Get-NormalizedSha256([string]$path) {
    $text = [IO.File]::ReadAllText($path)
    $text = $text -replace "`r`n", "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    return ([BitConverter]::ToString($__sha.ComputeHash($bytes))).Replace('-', '').ToLower()
}
function Bad($m)  { Write-Output "FAIL  $m"; $script:fail++ }
function Note($m) { Write-Output "WARN  $m"; $script:warn++ }

try {
    $regFull = Join-Path $repo $RegisterPath
    if (-not (Test-Path $regFull)) { Bad "approval register missing: $RegisterPath"; Write-Output "RESULT: FAIL"; exit 1 }
    $reg = Get-Content $regFull -Raw | ConvertFrom-Json
    Ok ("register parses ($($reg.articles.Count) rows)")

    $tracked = @(& git ls-files)
    $diskSlugs = @($tracked | Where-Object { $_ -match '^articles/[^/]+\.html$' -and $_ -notmatch '-evidence\.html$' } |
        ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) } | Sort-Object)
    $regSlugs = @($reg.articles | ForEach-Object { $_.slug } | Sort-Object)

    $missing = @($diskSlugs | Where-Object { $regSlugs -notcontains $_ })
    $extra = @($regSlugs | Where-Object { $diskSlugs -notcontains $_ })
    if ($missing.Count -eq 0) { Ok "every published article has a register row ($($diskSlugs.Count))" }
    else { Bad ("articles with no register row: " + ($missing -join ', ')) }
    if ($extra.Count -eq 0) { Ok 'register holds no row for an unpublished article' }
    else { Bad ("register rows with no article on disk: " + ($extra -join ', ')) }
    if ($regSlugs.Count -ne @($regSlugs | Select-Object -Unique).Count) { Bad 'duplicate slug rows in the register' } else { Ok 'no duplicate rows' }

    Write-Output ''
    Write-Output '--- revision integrity ---'
    foreach ($row in $reg.articles) {
        $full = Join-Path $repo ('articles\' + $row.slug + '.html')
        if (-not (Test-Path $full)) { Bad ("$($row.slug) : file missing"); continue }
        $now = Get-NormalizedSha256 $full
        if ($row.revision.hash -eq $now) { Ok ("$($row.slug) : file matches the recorded revision") }
        else {
            if ($row.status -eq 'APPROVED - PUBLISHED') {
                Bad ("$($row.slug) : APPROVED revision has drifted - approved $($row.revision.hash.Substring(0,12)).. now $($now.Substring(0,12))..")
            } else {
                Note ("$($row.slug) : revision differs from the snapshot, but no approval was recorded for it either way")
            }
        }
    }

    Write-Output ''
    Write-Output '--- approval coverage ---'
    $approved = @($reg.articles | Where-Object { $_.status -eq 'APPROVED - PUBLISHED' })
    $unrecorded = @($reg.articles | Where-Object { $_.status -ne 'APPROVED - PUBLISHED' })
    foreach ($r in $approved) {
        if ([string]::IsNullOrWhiteSpace($r.approvingParty) -or [string]::IsNullOrWhiteSpace($r.approvalDate) -or [string]::IsNullOrWhiteSpace($r.approvalEvidence)) {
            Bad ("$($r.slug) : marked approved but the authority, date or evidence is blank")
        }
    }
    Ok ("articles with a fully evidenced approval: $($approved.Count)")
    if ($unrecorded.Count -gt 0) {
        Note ("published with no recorded approval: $($unrecorded.Count) (" + (($unrecorded | ForEach-Object { $_.slug }) -join ', ') + ")")
        Write-Output '      These were published before this register existed. The register records that fact'
        Write-Output '      rather than reconstructing an approval that cannot be evidenced.'
    }

    Write-Output ''
    Write-Output ("REGISTER: PASS={0} FAIL={1} WARN={2}" -f $pass, $fail, $warn)
    if ($fail -gt 0) { Write-Output 'RESULT: FAIL'; exit 1 }
    Write-Output 'RESULT: PASS'
    exit 0
}
finally { Pop-Location }
