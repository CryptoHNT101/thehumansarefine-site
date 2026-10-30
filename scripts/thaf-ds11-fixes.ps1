<#
  thaf-ds11-fixes.ps1  --  Day Shift 11 bounded fixes
  --------------------------------------------------
  Two edits, both idempotent, both verifiable with -Check:

  1. CSS CACHE-BUSTING
     Day Shift 6 changed styles.css and assets/article.css, but every page
     linked them with a bare href, so returning readers (and any intermediary
     cache) could keep the previous stylesheet. This stamps a content hash
     query (?v=<sha256-first-10>) onto each stylesheet link. Any existing ?v=
     is stripped by the same pattern, so re-running after a CSS edit re-stamps
     cleanly, and re-running with no CSS change writes nothing.

  2. MISLEADING BUILD BANNER
     Seven intentionally public pages carried "UNPUBLISHED DEVELOPMENT BUILD"
     and "THAF // RELEASE 2 // DEVELOPMENT". The site is published; those
     labels were false. They become "PUBLISHED EDITION" and
     "THAF // RELEASE 2 // LIVE".
     Genuine labels are NOT touched: "NEWSWIRE: COMING SOON" on the homepage
     and quoted "coming soon" text inside articles stay exactly as they are.

  -Check writes nothing and reports which files would change.
#>

[CmdletBinding()]
param(
  [switch]$Check,
  [string]$Root = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
Set-Location $Root

function Get-ShortHash([string]$RelativePath) {
  $full = Join-Path $Root $RelativePath
  if (-not (Test-Path $full)) { throw "stylesheet not found: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($full)
  $sha = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  $hex = ([System.BitConverter]::ToString($sha)).Replace('-', '').ToLowerInvariant()
  return $hex.Substring(0, 10)
}

$cssHash = Get-ShortHash 'styles.css'
$artHash = Get-ShortHash 'assets/article.css'
Write-Output "styles.css       hash=$cssHash"
Write-Output "article.css      hash=$artHash"

# Files excluded: harness scratch trees, git internals and the unpublished
# Frontier Disclosure Watch collector.
$htmlFiles = Get-ChildItem -Path $Root -Recurse -Filter *.html | Where-Object {
  $_.FullName -notmatch '\\tmp\\' -and
  $_.FullName -notmatch '\\fdw\\' -and
  $_.FullName -notmatch '\\\.git\\'
}

$changed = 0
$checked = 0
$detail = New-Object System.Collections.ArrayList

foreach ($f in $htmlFiles) {
  $checked++
  $text = [System.IO.File]::ReadAllText($f.FullName)
  $original = $text

  # --- 1. cache-bust paths -------------------------------------------------
  # Each pattern consumes an optional existing ?v=<hex> and replaces it, so the
  # operation is idempotent and never stacks queries.
  $text = $text -replace 'href="\.\./styles\.css(\?v=[0-9a-f]+)?"',           "href=`"../styles.css?v=$cssHash`""
  $text = $text -replace 'href="styles\.css(\?v=[0-9a-f]+)?"',                "href=`"styles.css?v=$cssHash`""
  $text = $text -replace 'href="\.\./assets/article\.css(\?v=[0-9a-f]+)?"',   "href=`"../assets/article.css?v=$artHash`""

  # --- 2. false build banner ----------------------------------------------
  $text = $text.Replace('THAF // RELEASE 2 // DEVELOPMENT', 'THAF // RELEASE 2 // LIVE')
  $text = $text.Replace('<span class="ok">&#9679;</span> UNPUBLISHED DEVELOPMENT BUILD',
                        '<span class="ok">&#9679;</span> PUBLISHED EDITION')

  if ($text -ne $original) {
    $changed++
    [void]$detail.Add($f.FullName.Replace($Root + '\', ''))
    if (-not $Check) {
      [System.IO.File]::WriteAllText($f.FullName, $text)
    }
  }
}

Write-Output ""
Write-Output "files scanned: $checked"
Write-Output "files changed: $changed"
foreach ($d in $detail) { Write-Output "  $d" }

# --- residual assertions ---------------------------------------------------
$udb = 0; $dev = 0; $bare = 0
foreach ($f in $htmlFiles) {
  $t = [System.IO.File]::ReadAllText($f.FullName)
  $udb += ([regex]::Matches($t, 'UNPUBLISHED DEVELOPMENT BUILD')).Count
  $dev += ([regex]::Matches($t, 'THAF // RELEASE 2 // DEVELOPMENT')).Count
  $bare += ([regex]::Matches($t, 'href="(\.\./)?(assets/)?(styles|article)\.css"')).Count
}
Write-Output ""
Write-Output "residual UNPUBLISHED DEVELOPMENT BUILD : $udb"
Write-Output "residual // DEVELOPMENT edition       : $dev"
Write-Output "residual unversioned stylesheet links : $bare"

if ($Check) {
  Write-Output ""
  Write-Output "CHECK MODE: no files written."
} else {
  Write-Output ""
  Write-Output "WRITE MODE: files updated."
}
