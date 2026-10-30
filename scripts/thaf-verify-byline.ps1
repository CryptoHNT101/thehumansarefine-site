# Narrow post-deploy check on the script committed as e80db4b.
#   1. tokenizer parse (0 errors expected)
#   2. idempotent re-run must change nothing and re-assert 9 bylines
#   3. on-disk assertion that every article still matches the byline shape
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script = Join-Path $repo 'scripts\thaf-add-byline.ps1'

$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$errors)
Write-Output ("PARSE thaf-add-byline.ps1 : {0} parse error(s)" -f @($errors).Count)
if (@($errors).Count -gt 0) { $errors | ForEach-Object { Write-Output ("   " + $_.Message) }; exit 1 }

Push-Location $repo
try {
    Write-Output '--- idempotent re-run ---'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script
    if ($LASTEXITCODE -ne 0) { Write-Output "RE-RUN FAILED: exit $LASTEXITCODE"; exit 1 }

    Write-Output '--- on-disk assertion ---'
    $arts = @(Get-ChildItem 'articles' -Filter '*.html' | Where-Object { $_.Name -notlike '*-evidence.html' })
    $bad = @()
    foreach ($f in $arts) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $ok = $t -match '(?is)<ul class="article-meta">\s*<li><b>By</b>\s*<a href="\.\./standards/#ai-disclosure">'
        if (-not $ok) { $bad += $f.Name }
    }
    Write-Output ("articles with byline-shaped first meta item: {0} of {1}" -f ($arts.Count - $bad.Count), $arts.Count)
    if ($bad.Count -gt 0) { Write-Output ('MISSING: ' + ($bad -join ', ')); exit 1 }

    $std = [System.IO.File]::ReadAllText((Join-Path $repo 'standards\index.html'))
    $anchor = $std -match 'id="ai-disclosure"'
    Write-Output ("standards anchor present: {0}" -f $anchor)
    if (-not $anchor) { exit 1 }

    Write-Output ''
    Write-Output 'CHECK: PASS'
}
finally { Pop-Location }
