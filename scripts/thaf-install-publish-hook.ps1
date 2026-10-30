# ============================================================================
# THE HUMANS ARE FINE - install the publish hook
#
# Copies the tracked scripts/hooks/pre-commit into .git/hooks/pre-commit so a
# commit that touches articles cannot leave the news sitemap stale.
#
# This changes how commits behave, so it is not run automatically - run it when
# you want it. -Uninstall puts the previous hook back.
# ============================================================================
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    $hooks = Join-Path $repo '.git\hooks'
    if (-not (Test-Path $hooks)) { throw 'Not a git repository (no .git/hooks).' }
    $dest = Join-Path $hooks 'pre-commit'
    $backup = Join-Path $hooks 'pre-commit.thaf-backup'

    if ($Uninstall) {
        if (Test-Path $backup) {
            Move-Item $backup $dest -Force
            Write-Output 'restored the previous pre-commit hook'
        } elseif (Test-Path $dest) {
            Remove-Item $dest
            Write-Output 'removed the THAF pre-commit hook'
        } else {
            Write-Output 'no THAF hook was installed'
        }
        return
    }

    if ((Test-Path $dest) -and -not (Test-Path $backup)) {
        Copy-Item $dest $backup
        Write-Output ("existing hook preserved as {0}" -f $backup)
    }
    Copy-Item (Join-Path $repo 'scripts\hooks\pre-commit') $dest -Force
    Write-Output ("installed {0}" -f $dest)
    Write-Output 'a commit touching articles/ now rebuilds the sitemaps and refuses if they disagree'
}
finally { Pop-Location }
