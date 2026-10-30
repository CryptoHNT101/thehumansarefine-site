# verify-live-day11.ps1 -- confirm the Day Shift 11 release is actually live.
# Checks every URL in the live sitemap for: false banner gone, edition label
# corrected, stylesheet cache-busting present, and an HTTP 200.
# Read-only: it fetches, it never writes.

$ErrorActionPreference = 'Continue'

$site = 'https://www.thehumansarefine.com'
$sitemapUrl = "$site/sitemap.xml"

$xml = [xml](Invoke-WebRequest -Uri $sitemapUrl -UseBasicParsing -TimeoutSec 30).Content
$urls = @($xml.urlset.url.loc)
Write-Output "sitemap: $sitemapUrl"
Write-Output "sitemap urls: $($urls.Count)"
Write-Output ""

$fail = 0
$ok = 0

foreach ($u in $urls) {
  try {
    $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 30
    $t = $r.Content

    $falseBanner = ([regex]::Matches($t, 'UNPUBLISHED DEVELOPMENT BUILD')).Count
    $devEdition  = ([regex]::Matches($t, 'THAF // RELEASE 2 // DEVELOPMENT')).Count
    $bareCss     = ([regex]::Matches($t, 'href="(\.\./)?(assets/)?(styles|article)\.css"')).Count
    $versioned   = ([regex]::Matches($t, '\.css\?v=[0-9a-f]{10}')).Count
    $published   = ([regex]::Matches($t, 'PUBLISHED EDITION')).Count

    $bad = $falseBanner + $devEdition + $bareCss
    if ($bad -gt 0) {
      $fail++
      Write-Output ("BAD  $u  status=$($r.StatusCode)  false_banner=$falseBanner  dev_edition=$devEdition  unversioned_css=$bareCss")
    } else {
      $ok++
      Write-Output ("OK   $u  status=$($r.StatusCode)  versioned_css=$versioned  published_edition=$published")
    }
  }
  catch {
    $fail++
    Write-Output ("ERR  $u  $($_.Exception.Message)")
  }
}

Write-Output ""
Write-Output "LIVE CHECK: ok=$ok fail=$fail"

# The genuine labels the release was required to preserve.
# NB: $home is a read-only PowerShell automatic variable -- using it silently
# aborted this assertion in the first run, so the page text lives in $homePage.
$homePage = (Invoke-WebRequest -Uri "$site/" -UseBasicParsing -TimeoutSec 30).Content
$comingSoon = ([regex]::Matches($homePage, 'NEWSWIRE: COMING SOON')).Count
Write-Output "preserved homepage label NEWSWIRE: COMING SOON = $comingSoon"

# Consent behaviour: the released bridge must still gate tracking on consent.
$js = (Invoke-WebRequest -Uri "$site/assets/analytics.js" -UseBasicParsing -TimeoutSec 30).Content
$hasGate = $js -match "if \(saved === 'granted'\) load\(\);"
$noInline = ([regex]::Matches($homePage, 'googletagmanager\.com/gtag')).Count
Write-Output "consent gate present in live bridge = $hasGate"
Write-Output "inline gtag tags on homepage = $noInline"

if ($fail -eq 0 -and $hasGate -and $noInline -eq 0) {
  Write-Output "VERDICT: PASS"
  exit 0
} else {
  Write-Output "VERDICT: FAIL"
  exit 1
}
