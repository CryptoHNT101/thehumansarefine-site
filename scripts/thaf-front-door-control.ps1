# ============================================================================
# Red control for scripts/thaf-verify-front-door.ps1
#
# Copies the release tree to a scratch directory, breaks exactly one internal
# link in index.html, serves the copy on a spare port, and requires the
# verifier to FAIL and to name the broken target. The release tree is not
# touched: this proves the checker discriminates without risking the artefact
# it is checking.
#
#   pwsh -File scripts/thaf-front-door-control.ps1
# ============================================================================
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scratch = Join-Path $env:TEMP ('thaf-control-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$port = 8399
$serverProc = $null

Write-Output ("scratch: " + $scratch)
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
try {
    # Copy the site, not the history.
    $items = @(Get-ChildItem -Path $repo -Force | Where-Object { $_.Name -notin @('.git', 'shots', 'node_modules') })
    foreach ($i in $items) {
        Copy-Item -Path $i.FullName -Destination $scratch -Recurse -Force
    }

    $target = Join-Path $scratch 'index.html'
    $html = [System.IO.File]::ReadAllText($target)
    $marker = '<a href="definitely-broken-9c1f.html">control</a>'
    $out = $html.Replace('<section id="about"', $marker + '<section id="about"')
    if ($out -ceq $html) { throw 'MUTATION DID NOT APPLY - refusing to report a control that did not control.' }
    [System.IO.File]::WriteAllText($target, $out, (New-Object System.Text.UTF8Encoding($false)))
    $applied = ([System.IO.File]::ReadAllText($target)).Contains('definitely-broken-9c1f.html')
    Write-Output ('MUTATION_APPLIED = ' + $applied)
    if (-not $applied) { throw 'mutation present in memory but not on disk' }

    $serverProc = Start-Process -FilePath 'powershell' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $repo 'scripts\thaf-serve-local.ps1'),
        '-Port', $port, '-Root', $scratch
    ) -PassThru -WindowStyle Hidden

    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 300
        try {
            $r = Invoke-WebRequest -Uri ("http://127.0.0.1:$port/") -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -eq 200) { $ready = $true; break }
        } catch { }
    }
    Write-Output ('SERVER_READY = ' + $ready)
    if (-not $ready) { throw 'the control server never came up; the control proves nothing and is reported as such.' }

    $log = Join-Path $env:TEMP ('thaf-control-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.log')
    & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repo 'scripts\thaf-verify-front-door.ps1') -BaseUrl ("http://127.0.0.1:$port") -Root $scratch *> $log
    $code = $LASTEXITCODE
    Write-Output ('CONTROL_EXIT = ' + $code)
    $named = @(Get-Content $log | Where-Object { $_ -match 'definitely-broken-9c1f' }).Count -gt 0
    $verdict = @(Get-Content $log | Where-Object { $_ -match '^RESULT' })
    Write-Output ('NAMED_THE_BROKEN_LINK = ' + $named)
    Write-Output ('VERDICT_LINE = ' + ($verdict -join ' '))
    Get-Content $log | Where-Object { $_ -match 'FAIL|TOTAL' } | ForEach-Object { Write-Output ('  ' + $_) }
    Remove-Item $log -Force -ErrorAction SilentlyContinue

    $ok = ($code -ne 0) -and $named
    Write-Output ''
    if ($ok) { Write-Output 'CONTROL VERDICT: PASS - the verifier fails when one internal link is broken, and names it' ; exit 0 }
    Write-Output 'CONTROL VERDICT: FAIL - the verifier did not go red on a broken link'
    exit 1
}
finally {
    if ($serverProc -and -not $serverProc.HasExited) { try { Stop-Process -Id $serverProc.Id -Force } catch { } }
    Start-Sleep -Milliseconds 400
    if (Test-Path $scratch) {
        try { Remove-Item $scratch -Recurse -Force } catch { }
    }
    Write-Output ('scratch removed = ' + (-not (Test-Path $scratch)))
}
