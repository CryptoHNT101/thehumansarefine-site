# submit-indexnow.ps1 - push site URLs to IndexNow (Bing, Yandex, Seznam) after a deploy.
#
# Why: Search Console shows what Google already knows, but it cannot make Google look. IndexNow is
# the only indexing channel that needs no account and no OAuth - the key file at the site root
# proves domain ownership, and a POST tells participating engines a URL changed. It does not make
# Google index anything (Google does not participate), so this complements Search Console rather
# than replacing it.
#
# Success codes are 200 (accepted) and 202 (accepted, key validation pending). Anything else is a
# real failure. Run after a deploy, or pass -All to resubmit the whole sitemap.
param(
    [string[]]$Url,
    [switch]$All,
    [string]$Sitemap = 'https://www.thehumansarefine.com/sitemap.xml',
    [string]$KeyFile,
    [string]$Host_ = 'www.thehumansarefine.com'
)
$ErrorActionPreference = 'Stop'

$siteRoot = Split-Path $PSScriptRoot -Parent
if (-not $KeyFile) {
    $k = Get-ChildItem -Path $siteRoot -Filter '*.txt' |
        Where-Object { $_.BaseName -match '^[0-9a-f]{32}$' } |
        Select-Object -First 1
    if (-not $k) { throw "No IndexNow key file found in $siteRoot. Expected <32 hex chars>.txt" }
    $KeyFile = $k.BaseName
}
$keyLocation = "https://$Host_/$KeyFile.txt"

# Verify the key is actually served before submitting; engines will fetch it and reject us silently.
try {
    $served = (Invoke-WebRequest -Uri $keyLocation -TimeoutSec 25 -UseBasicParsing).Content.Trim()
} catch {
    throw "IndexNow key is not live at $keyLocation - deploy it first. ($($_.Exception.Message))"
}
if ($served -ne $KeyFile) { throw "Key file content mismatch: served '$served', expected '$KeyFile'" }
Write-Host "key verified live: $keyLocation"

if ($All -or -not $Url) {
    $sm = (Invoke-WebRequest -Uri $Sitemap -TimeoutSec 25 -UseBasicParsing).Content
    $Url = @([regex]::Matches($sm, '<loc>(.*?)</loc>') | ForEach-Object { $_.Groups[1].Value })
}
$Url = @($Url | Where-Object { $_ -match '^https?://' } | Select-Object -Unique)
if ($Url.Count -eq 0) { throw "No URLs to submit." }
Write-Host "submitting $($Url.Count) url(s)"

$body = @{ host = $Host_; key = $KeyFile; keyLocation = $keyLocation; urlList = $Url } | ConvertTo-Json -Depth 4
try {
    $r = Invoke-WebRequest -Uri 'https://api.indexnow.org/indexnow' -Method Post `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
        -ContentType 'application/json; charset=utf-8' -TimeoutSec 40 -UseBasicParsing
    $status = [int]$r.StatusCode
} catch {
    $status = $_.Exception.Response.StatusCode.value__
}

switch ($status) {
    200 { Write-Host "IndexNow: 200 accepted"; exit 0 }
    202 { Write-Host "IndexNow: 202 accepted (key validation pending)"; exit 0 }
    400 { Write-Host "IndexNow: 400 bad request format"; exit 1 }
    403 { Write-Host "IndexNow: 403 key not valid - check $keyLocation"; exit 1 }
    422 { Write-Host "IndexNow: 422 urls do not match host, or key file unreachable"; exit 1 }
    429 { Write-Host "IndexNow: 429 too many requests - back off"; exit 1 }
    default { Write-Host "IndexNow: unexpected status $status"; exit 1 }
}
