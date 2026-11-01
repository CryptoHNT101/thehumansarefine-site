# ============================================================================
# THE HUMANS ARE FINE - browser verification of the public front door
#
# Renders the release candidate in headless Chrome at three widths and reports
# what the browser measured, not what the markup implies:
#
#   - horizontal overflow per page per width (scrollWidth - clientWidth), plus
#     the elements that stick out when there are any
#   - the primary navigation's rendered item count and whether it fits
#   - required text actually present in the rendered DOM
#   - screenshots for the record
#
# Method: a same-origin probe page frames the target at the width under test,
# reads the framed document's own geometry, and writes the numbers into its
# <title>. Chrome is then asked to dump the probe's DOM. This uses the real
# engine and the real stylesheets; it is not a source inspection.
#
#   pwsh -File scripts/thaf-browser-verify.ps1 -BaseUrl http://127.0.0.1:8322
# ============================================================================
param(
    [string]$BaseUrl = 'http://127.0.0.1:8322',
    [string]$Root = '',
    [string]$ShotDir = 'shots-frontdoor'
)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$Root = (Resolve-Path $Root).Path

$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
if (-not (Test-Path $chrome)) { $chrome = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' }
if (-not (Test-Path $chrome)) { throw 'No Chromium-family browser found to render with. Reporting as BLOCKED, not as a pass.' }

$profileDir = Join-Path $env:TEMP ('thaf-chrome-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$probePath = Join-Path $Root '_browser-probe.html'
$shotPath = Join-Path $Root $ShotDir
New-Item -ItemType Directory -Path $shotPath -Force | Out-Null

$probeHtml = @'
<!doctype html><meta charset="utf-8"><title>PROBE-PENDING</title>
<style>html,body{margin:0;padding:0;background:#000}iframe{border:0;display:block}</style>
<body>
<script>
(function(){
  var p=new URLSearchParams(location.search);
  var u=p.get('u')||'/'; var w=parseInt(p.get('w')||'1440',10);
  var res=document.createElement('div'); res.id='res'; res.textContent='';
  res.style.cssText='position:absolute;left:-9999px;top:0;width:1px;height:1px;overflow:hidden';
  document.body.appendChild(res);
  var f=document.createElement('iframe');
  f.style.width=w+'px'; f.style.height='1000px';
  var done=false;
  function measure(){
    if(done)return; done=true;
    try{
      var d=f.contentDocument, de=d.documentElement;
      var sw=de.scrollWidth, cw=de.clientWidth;
      var offenders=[];
      var all=d.querySelectorAll('body *');
      for(var i=0;i<all.length;i++){
        var r=all[i].getBoundingClientRect();
        if(r.right>cw+1 && r.width>0){
          offenders.push(all[i].tagName.toLowerCase()+'.'+String(all[i].className||'').split(' ')[0]+'@'+Math.round(r.right));
          if(offenders.length>=8)break;
        }
      }
      var nav=d.querySelector('nav.nav');
      var navN=nav?nav.querySelectorAll('a').length:-1;
      var navH=nav?Math.round(nav.getBoundingClientRect().height):-1;
      var parts=['PRO','BE2',u,w,sw,cw,(sw-cw),navN,navH,(offenders.join(';')||'none')].join('|');
      res.textContent=parts;
      document.title=parts;
    }catch(e){
      res.textContent=['PRO','BE2-ERR',u,(e&&e.message)].join('|');
    }
  }
  // Listener first, then src, then append: on a local server the load event can
  // fire before a listener attached afterwards would ever hear it.
  f.addEventListener('load', measure);
  f.src=u;
  document.body.appendChild(f);
  setTimeout(measure, 1500);
})();
</script>
</body>
'@
[System.IO.File]::WriteAllText($probePath, $probeHtml, (New-Object System.Text.UTF8Encoding($false)))

$script:pass = 0
$script:fail = 0
function Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { $script:pass++; Write-Output ('  PASS  {0}{1}' -f $Name, $(if ($Detail) { '  [' + $Detail + ']' } else { '' })) }
    else { $script:fail++; Write-Output ('  FAIL  {0}{1}' -f $Name, $(if ($Detail) { '  [' + $Detail + ']' } else { '' })) }
}

# chrome.exe hands the work to a child process and the launcher returns at once,
# so & $chrome | Out-String captures nothing. Start-Process -Wait with redirected
# streams is the only reliable way to get the DOM back.
$script:chromeOut = Join-Path $env:TEMP ('thaf-chrome-out-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.txt')
$script:chromeErr = Join-Path $env:TEMP ('thaf-chrome-err-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.txt')
function Invoke-Chrome {
    param([string[]]$ChromeArgs)
    if (Test-Path $script:chromeOut) { Remove-Item $script:chromeOut -Force }
    if (Test-Path $script:chromeErr) { Remove-Item $script:chromeErr -Force }
    $p = Start-Process -FilePath $chrome -ArgumentList $ChromeArgs -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $script:chromeOut -RedirectStandardError $script:chromeErr
    $text = ''
    if (Test-Path $script:chromeOut) { $text = [System.IO.File]::ReadAllText($script:chromeOut) }
    return $text
}

$origin = $BaseUrl.TrimEnd('/')
$widths = @(1440, 768, 390)
$targets = @(
    @{ Path = '/';                    Label = 'homepage' },
    @{ Path = '/send-your-agent.html'; Label = 'send-your-agent' },
    @{ Path = '/standards/verification.html'; Label = 'verification-standard' },
    @{ Path = '/machines-are-talking.html'; Label = 'machines-are-talking' },
    @{ Path = '/newswire.html';       Label = 'agent-newswire' },
    @{ Path = '/news/index.html';     Label = 'news-archive' },
    @{ Path = '/standards/';          Label = 'editorial-standards' },
    @{ Path = '/articles/wall-street-ai-bet.html'; Label = 'lead-article' },
    @{ Path = '/disclosure-watch/';   Label = 'disclosure-watch' }
)

$measurements = @()
try {
    Write-Output '--- rendered layout measurements ---'
    foreach ($t in $targets) {
        foreach ($w in $widths) {
            $url = "{0}/_browser-probe.html?u={1}&w={2}" -f $origin, [uri]::EscapeDataString($t.Path), $w
            $dom = Invoke-Chrome @(
                '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
                '--disable-extensions', '--hide-scrollbars',
                ('--user-data-dir=' + $profileDir),
                ('--window-size=' + ($w + 40) + ',1100'),
                '--virtual-time-budget=8000',
                '--dump-dom', $url
            )
            # Read the runtime-filled result element only. The probe builds its
            # marker from fragments so this pattern cannot match the probe's own
            # script source, which --dump-dom also returns.
            $m = [regex]::Match($dom, 'id="res"[^>]*>(PRO\|BE2\|[^<]*)</div>')
            if (-not $m.Success) {
                $err = [regex]::Match($dom, 'id="res">(PRO\|BE2-ERR\|[^<]*)|</div>')
                $measurements += [pscustomobject]@{ page = $t.Label; width = $w; overflow = $null; nav = -1; navH = -1; offenders = 'PROBE-FAILED' }
                continue
            }
            $f = $m.Groups[1].Value.Split('|')
            $off = if ($f.Count -ge 10) { ($f[9..($f.Count - 1)] -join '|') } else { 'none' }
            $measurements += [pscustomobject]@{
                page       = $t.Label
                width      = [int]$f[3]
                overflow   = [int]$f[6]
                nav        = [int]$f[7]
                navH       = [int]$f[8]
                offenders  = $off
            }
        }
    }

    Write-Output ('  {0,-24} {1,-6} {2,-9} {3,-9} {4}' -f 'PAGE', 'WIDTH', 'OVERFLOW', 'NAV-ITEMS', 'WIDEST-ELEMENT')
    foreach ($r in $measurements) {
        Write-Output ('  {0,-24} {1,-6} {2,-9} {3,-9} {4}' -f $r.page, $r.width, $(if ($null -eq $r.overflow) { 'FAILED' } else { $r.overflow }), $r.nav, $r.offenders)
    }

    foreach ($r in $measurements) {
        Check ("{0} at {1}px: no horizontal overflow" -f $r.page, $r.width) ($null -ne $r.overflow -and $r.overflow -le 0) ("overflow=" + $r.overflow + $(if ($r.offenders -ne 'none' -and $r.overflow -gt 0) { ' widest=' + $r.offenders } else { '' }))
        Check ("{0} at {1}px: primary nav renders nine items" -f $r.page, $r.width) ($r.nav -eq 9) ("nav=" + $r.nav)
    }

    Write-Output '--- rendered content checks ---'
    $domHome = Invoke-Chrome @('--headless=new', '--disable-gpu', '--no-first-run', '--hide-scrollbars', ('--user-data-dir=' + $profileDir), '--window-size=1440,1100', '--virtual-time-budget=6000', '--dump-dom', ($origin + '/'))
    foreach ($needle in @('SEND YOUR AGENT', 'THE MACHINES ARE TALKING', 'AGENT NEWSWIRE', 'THE VERIFICATION STANDARD', 'Wall Street')) {
        Check ("homepage renders '$needle'") ($domHome -match [regex]::Escape($needle))
    }
    $domSya = Invoke-Chrome @('--headless=new', '--disable-gpu', '--no-first-run', '--hide-scrollbars', ('--user-data-dir=' + $profileDir), '--window-size=1440,1100', '--virtual-time-budget=6000', '--dump-dom', ($origin + '/send-your-agent.html'))
    # ASCII-only on purpose: this .ps1 has no BOM, so Windows PowerShell reads a
    # literal em dash in the pattern as two ANSI bytes and the match silently
    # never fires. Assert on structure plus the words instead.
    Check 'Send Your Agent renders its coming-soon banner' (($domSya -match 'class="sya-banner"') -and ($domSya -match 'coming soon'))
    Check 'Send Your Agent renders the endpoint table' ($domSya -match '/api/newswire/submit')
    $domTmt = Invoke-Chrome @('--headless=new', '--disable-gpu', '--no-first-run', '--hide-scrollbars', ('--user-data-dir=' + $profileDir), '--window-size=1440,1100', '--virtual-time-budget=6000', '--dump-dom', ($origin + '/machines-are-talking.html'))
    Check 'TMIT renders the not-live status panel' ($domTmt -match 'No discussion is live')

    Write-Output '--- screenshots ---'
    foreach ($t in @(@{ Path = '/'; Label = 'homepage' }, @{ Path = '/send-your-agent.html'; Label = 'send-your-agent' }, @{ Path = '/standards/verification.html'; Label = 'verification-standard' }, @{ Path = '/machines-are-talking.html'; Label = 'machines-are-talking' }, @{ Path = '/newswire.html'; Label = 'agent-newswire' })) {
        foreach ($w in @(1440, 390)) {
            $file = Join-Path $shotPath ('{0}-{1}.png' -f $t.Label, $w)
            # Screenshot the framed view, not the raw page. Headless Chrome lays
            # the page out at its default viewport regardless of --window-size,
            # so a direct --screenshot at 390 is a 390px CROP of a ~1060px
            # layout: it looks like overflow and is not. The frame forces the
            # layout width, so the pixels match the measurement.
            $shotUrl = "{0}/_browser-probe.html?u={1}&w={2}" -f $origin, [uri]::EscapeDataString($t.Path), $w
            $null = Invoke-Chrome @('--headless=new', '--disable-gpu', '--no-first-run', '--hide-scrollbars', '--force-device-scale-factor=1', ('--user-data-dir=' + $profileDir), ('--window-size={0},1200' -f $w), '--virtual-time-budget=8000', ('--screenshot=' + $file), $shotUrl)
            $ok = (Test-Path $file) -and ((Get-Item $file).Length -gt 20000)
            Check ("screenshot {0} at {1}px" -f $t.Label, $w) $ok ("bytes=" + $(if (Test-Path $file) { (Get-Item $file).Length } else { 0 }))
        }
    }

    Write-Output ''
    Write-Output ('TOTAL: pass={0} fail={1}' -f $script:pass, $script:fail)
    if ($script:fail -gt 0) { Write-Output 'RESULT: FAIL'; exit 1 }
    Write-Output 'RESULT: PASS'
    exit 0
}
finally {
    if (Test-Path $probePath) { Remove-Item $probePath -Force }
    if (Test-Path $profileDir) { try { Remove-Item $profileDir -Recurse -Force } catch { } }
}
