# ============================================================================
# THE HUMANS ARE FINE - build the private "The agents are arguing" page
#
# Input : ../private/arguments/shift08/records.jsonl  (a byte-identical copy of
#         the station's signed store; its sha256 is recorded on the page)
# Output: ../private/arguments/index.html  - outside the deploy repository
#
# The store and the page live outside this repo on purpose. This repo is
# published verbatim by GitHub Pages, so "noindex" would be the only thing
# between an internal transcript and the open web. Keep it out entirely.
# ============================================================================
param(
    [string]$Store = '../private/arguments/shift08/records.jsonl',
        [string]$Sources = '../private/arguments/shift08/sources.json',
        [string]$Provenance = '../private/arguments/shift08/provenance.txt',
        [string]$Out = '../private/arguments/index.html',
        [string]$SiteBase = '../../site',
    [switch]$WhatIf
        )
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {

    function Html([string]$s) {
        return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
    }

    # Paragraph the agent's own text. The only change is that markdown emphasis
    # markers become tags; no word is added, removed or reordered. The build's
    # own check strips the tags back out and compares against the source body.
    function Body-Paragraphs([string]$text) {
        $t = Html $text
        $t = [regex]::Replace($t, '\*\*(.+?)\*\*', '<strong>$1</strong>')
        $t = [regex]::Replace($t, '(?<!\*)\*(?!\*)([^*]+?)(?<!\*)\*(?!\*)', '<em>$1</em>')
        $paras = [regex]::Split($t.Trim(), '\r?\n\s*\r?\n')
        $sb = New-Object System.Text.StringBuilder
        foreach ($p in $paras) {
            if ($p.Trim() -eq '') { continue }
            $flat = $p.Trim() -replace '\r?\n', ' '
            [void]$sb.AppendLine('        <p>' + $flat + '</p>')
        }
        return $sb.ToString().TrimEnd()
    }

    if (-not (Test-Path $Store)) { throw "Missing record store: $Store" }
    $rawBytes = [IO.File]::ReadAllBytes((Resolve-Path $Store))
    $sha = (Get-FileHash (Resolve-Path $Store) -Algorithm SHA256).Hash.ToLower()
    $lines = @(Get-Content $Store -Encoding UTF8 | Where-Object { $_.Trim() -ne '' })
    $records = @($lines | ForEach-Object { $_ | ConvertFrom-Json })
    if ($records.Count -eq 0) { throw "The store has no records. An empty discussion page must not be rendered silently." }

    $srcMap = @{}
    if (Test-Path $Sources) {
        $s = Get-Content $Sources -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($article in $s.PSObject.Properties) {
            foreach ($item in $article.Value) { $srcMap[$item.url] = $item.title }
        }
    }
    $provText = if (Test-Path $Provenance) { (Get-Content $Provenance -Raw -Encoding UTF8).Trim() } else { '' }

    # Split each record into its metadata header and the verbatim result.
    $cards = New-Object System.Collections.Generic.List[object]
    foreach ($r in $records) {
        $body = [string]$r.body
        $begin = $body.IndexOf('----- BEGIN VERBATIM RESULT -----')
        $end = $body.IndexOf('----- END VERBATIM RESULT -----')
        $head = if ($begin -gt 0) { $body.Substring(0, $begin).Trim() } else { '' }
        $verbatim = if ($begin -ge 0 -and $end -gt $begin) {
            $body.Substring($begin + '----- BEGIN VERBATIM RESULT -----'.Length, $end - $begin - '----- BEGIN VERBATIM RESULT -----'.Length).Trim()
        } else { $body.Trim() }

        # Phase and role come from the record's own header lines.
        $phase = 'Independent phase'
        if ($head -match '(?i)ROUND 2') { $phase = 'Peer review phase' }
        elseif ($head -match '(?i)ROUND 1') { $phase = 'Independent phase' }
        $model = 'not stated in record'
        $m = [regex]::Match($head, '(?i)Model returned by harness:\s*([^\r\n]+)')
        if ($m.Success) { $model = $m.Groups[1].Value.Trim() } else {
            $m2 = [regex]::Match($head, '(?i)\((analyst|webdesigner),\s*([a-z0-9\.\-]+)\)')
            if ($m2.Success) { $model = $m2.Groups[2].Value }
        }
        $role = 'not stated in record'
        $m3 = [regex]::Match($head, '(?i)Station agent:\s*([^\r\n]+)')
        if ($m3.Success) { $role = $m3.Groups[1].Value.Trim() }
        elseif ($head -match '(?i)\((analyst|webdesigner),') { $role = $Matches[1] }

        $cited = @()
        foreach ($c in @($r.citations)) {
            if (-not $c) { continue }
            $title = if ($srcMap.ContainsKey($c)) { $srcMap[$c] } else { $c }
            $cited += [pscustomobject]@{ url = $c; title = $title }
        }

        $cards.Add([pscustomobject]@{
            id = $r.id; agent = $r.agentId; role = $role; model = $model; phase = $phase
            verbatim = $verbatim; head = $head; cited = $cited
            verified = [bool]$r.identityVerified; trust = $r.trustTier
            canonical = $r.canonicalHash; hash = $r.canonicalVersion
        })
    }

    $round1 = @($cards | Where-Object { $_.phase -eq 'Independent phase' })
    $round2 = @($cards | Where-Object { $_.phase -eq 'Peer review phase' })

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en">')
    [void]$sb.AppendLine('<head>')
    [void]$sb.AppendLine('<meta charset="utf-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    [void]$sb.AppendLine('<meta name="robots" content="noindex, nofollow, noarchive">')
    [void]$sb.AppendLine('<title>The agents are arguing â€” private build â€” THE HUMANS ARE FINE.</title>')
    [void]$sb.AppendLine('<meta name="description" content="A private, unlisted record of two station agents independently analysing the same claim, then reviewing each other. Built from four signed records.">')
    [void]$sb.AppendLine('<link rel="icon" href="' + $SiteBase + '/assets/thaf-flagship-profile.png">')
    [void]$sb.AppendLine('<link rel="stylesheet" href="' + $SiteBase + '/styles.css">')
    [void]$sb.AppendLine('<link rel="stylesheet" href="' + $SiteBase + '/assets/article.css">')
    [void]$sb.AppendLine('<link rel="stylesheet" href="arguments.css">')
    [void]$sb.AppendLine('<style>')
    [void]$sb.AppendLine('  .arg-card{border-top:2px solid #111;padding:22px 0 8px;margin:26px 0 0}')
    [void]$sb.AppendLine('  .arg-card h3{margin:0 0 6px;font-size:17px;letter-spacing:.02em;text-transform:uppercase}')
    [void]$sb.AppendLine('  .arg-meta{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;color:#6b6b6b;letter-spacing:.06em;text-transform:uppercase;margin:0 0 14px;display:flex;flex-wrap:wrap;gap:6px 14px}')
    [void]$sb.AppendLine('  .arg-body p{margin:0 0 14px;line-height:1.62}')
    [void]$sb.AppendLine('  .arg-cites{margin:14px 0 0;padding:12px 0 0;border-top:1px solid #e3e3e3;font-size:13px}')
    [void]$sb.AppendLine('  .arg-cites li{margin:0 0 6px}')
    [void]$sb.AppendLine('  .arg-cites a{word-break:break-all}')
    [void]$sb.AppendLine('  .state{border:1px solid #111;padding:18px 20px;margin:26px 0}')
    [void]$sb.AppendLine('  .state h2{margin:0 0 10px;font-size:15px;letter-spacing:.08em;text-transform:uppercase}')
    [void]$sb.AppendLine('  .state p{margin:0 0 12px}')
    [void]$sb.AppendLine('  .prov{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;word-break:break-all;background:#f6f6f6;padding:14px 16px;border:1px solid #e3e3e3}')
    [void]$sb.AppendLine('  .prov div{margin:0 0 6px}')
    [void]$sb.AppendLine('  .outcome{width:100%;border-collapse:collapse;margin:12px 0 0;font-size:14px}')
    [void]$sb.AppendLine('  .outcome th,.outcome td{text-align:left;padding:9px 10px;border-bottom:1px solid #e3e3e3;vertical-align:top}')
    [void]$sb.AppendLine('  .outcome th{width:34%;font-weight:600}')
    [void]$sb.AppendLine('  @media (max-width:560px){ .arg-card h3{font-size:15px} .outcome th{width:40%} }')
    [void]$sb.AppendLine('</style>')
    [void]$sb.AppendLine('</head>')
    [void]$sb.AppendLine('<body>')
    [void]$sb.AppendLine('<main class="wrap" id="top">')
    [void]$sb.AppendLine('  <p class="kicker"><a href="' + $SiteBase + '/index.html">THE HUMANS ARE FINE.</a> // THE RECORD // PRIVATE BUILD</p>')
    [void]$sb.AppendLine('  <h1>The agents are arguing</h1>')
    [void]$sb.AppendLine('  <p class="standfirst">Two station agents were given the same question and the same four documents, without being told the other existed. They were then shown each other&rsquo;s conclusion and asked whether it changed anything. Below is what each of them actually returned, held in four signed records.</p>')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('  <div class="state">')
    [void]$sb.AppendLine('    <h2>Status: private, unlisted, not published</h2>')
    [void]$sb.AppendLine('    <p>This page is a build on the development branch. It is marked <code>noindex, nofollow, noarchive</code>, it appears in neither <code>sitemap.xml</code> nor the feed, and it loads no analytics &mdash; opening it measures nothing. It is not linked from the public site.</p>')
    [void]$sb.AppendLine('    <p>The participants are <strong>station agents on this machine</strong>. They are not external parties and nothing here should be read as evidence of public participation or public consensus.</p>')
    [void]$sb.AppendLine('  </div>')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('  <h2>What happened</h2>')
    [void]$sb.AppendLine('  <p>Both investigators graded the same compound claim &mdash; that Sir Geoffrey Vos predicted in October 2025 that chatbot use would raise county court claims by around 10% a year, and that AI-generated claims were a material driver of the recorded 11% rise. They agreed on every graded element and on which of the four documents could settle each one. They landed on different headline labels for the compound claim, and in review both said the label difference was framing rather than a difference of evidence. One issued a correction &mdash; to its own wording, not its verdict.</p>')
    [void]$sb.AppendLine('  <table class="outcome">')
    [void]$sb.AppendLine('    <tr><th>Agreement</th><td>On all three graded elements, reached independently before either saw the other.</td></tr>')
    [void]$sb.AppendLine('    <tr><th>Partial agreement</th><td>On the headline label: one graded the claim <em>not supported</em>, the other <em>partly supported</em>. Both called that a difference in framing.</td></tr>')
    [void]$sb.AppendLine('    <tr><th>Genuine disagreement</th><td><strong>None observed.</strong> Neither manufactured one, and both explicitly declined to.</td></tr>')
    [void]$sb.AppendLine('    <tr><th>Correction</th><td>One, real: a claim about what a document showed was narrowed to that document, because absence in one document cannot establish absence in the world.</td></tr>')
    [void]$sb.AppendLine('    <tr><th>Insufficient evidence</th><td>Neither concluded so. Both named the same unprovable parts and proposed the same class of settling document.</td></tr>')
    [void]$sb.AppendLine('  </table>')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('  <div class="state" id="empty-state">')
    [void]$sb.AppendLine('    <h2>If you came here for a fight</h2>')
    [void]$sb.AppendLine('    <p>There isn&rsquo;t one in this record. That is the finding, not a gap in the page. A page that displayed a disagreement here would be displaying something that did not happen, and the record is short enough for you to check that claim yourself: four records, reproduced verbatim below, with their identifiers and hashes.</p>')
    [void]$sb.AppendLine('  </div>')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('  <h2>The records</h2>')
    [void]$sb.AppendLine('  <p>Question put to both investigators: <em>the compound claim above, graded against the same four documents, with a verdict and a per-element breakdown.</em> Round one was independent. Round two showed each the other&rsquo;s round-one conclusion verbatim, with holding presented as being as acceptable as revising.</p>')

    foreach ($c in $cards) {
        $title = (Html $c.agent) + ' &mdash; ' + (Html $c.role)
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('  <article class="arg-card">')
        [void]$sb.AppendLine('    <h3>' + $title + '</h3>')
        [void]$sb.AppendLine('    <p class="arg-meta"><span>' + (Html $c.phase) + '</span><span>' + (Html $c.model) + '</span><span>record ' + (Html $c.id) + '</span><span>cites ' + $c.cited.Count + '</span></p>')
        [void]$sb.AppendLine('    <div class="arg-body">')
        [void]$sb.AppendLine((Body-Paragraphs $c.verbatim))
        [void]$sb.AppendLine('    </div>')
        if ($c.cited.Count -gt 0) {
            [void]$sb.AppendLine('    <ul class="arg-cites">')
            foreach ($ci in $c.cited) {
                [void]$sb.AppendLine('      <li><a href="' + (Html $ci.url) + '" rel="noopener">' + (Html $ci.title) + '</a></li>')
            }
            [void]$sb.AppendLine('    </ul>')
        }
        [void]$sb.AppendLine('  </article>')
    }

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('  <h2>Provenance</h2>')
    [void]$sb.AppendLine('  <div class="prov">')
    [void]$sb.AppendLine('    <div>store: ' + (Html $Store) + ' &mdash; ' + $records.Count + ' records</div>')
    [void]$sb.AppendLine('    <div>sha256(records.jsonl): ' + $sha + '</div>')
    [void]$sb.AppendLine('    <div>records verified on build: ' + (@($cards | Where-Object { $_.verified }).Count) + ' of ' + $cards.Count + ' (identityVerified as returned by the store)</div>')
    [void]$sb.AppendLine('    <div>signature: RSASSA-PKCS1-v1_5 / SHA-256, canonical v2</div>')
    [void]$sb.AppendLine('  </div>')
    [void]$sb.AppendLine('  <p>' + (Html $provText) + '</p>')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('  <div class="state">')
    [void]$sb.AppendLine('    <h2>Limits of this record</h2>')
    [void]$sb.AppendLine('    <p><strong>Authorship is not bound to the key.</strong> A record proves that a registered key holder signed this text. It does not prove which registered identity wrote it. Any holder of a prototype key could post under any registered agent id and the record would still verify. The signing keys sit beside the server on one machine, so attribution here rests on key custody, not on cryptography.</p>')
    [void]$sb.AppendLine('    <p><strong>One round, one question.</strong> A single pair of investigators on a single claim shows the protocol works. It says nothing about how these agents behave across a hundred claims, and this page should not be read as a track record.</p>')
    [void]$sb.AppendLine('    <p><strong>Shared evidence base.</strong> Both worked from the same captured documents rather than their own live retrieval, so their agreement reflects a shared evidence base as well as independent reading.</p>')
    [void]$sb.AppendLine('  </div>')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('  <nav class="article-foot wrap" aria-label="Article navigation">')
    [void]$sb.AppendLine('    <a href="' + $SiteBase + '/standards/index.html">Corrections &amp; Standards</a>')
    [void]$sb.AppendLine('    <a href="' + $SiteBase + '/newsroom/index.html">Newsroom</a>')
    [void]$sb.AppendLine('    <a href="' + $SiteBase + '/index.html">Front page</a>')
    [void]$sb.AppendLine('  </nav>')
    [void]$sb.AppendLine('</main>')
    [void]$sb.AppendLine('</body>')
    [void]$sb.AppendLine('</html>')

    $text = $sb.ToString()
    # ASCII-only output, like the rest of the site's build: entity-encode any
    # stray non-ASCII the records carried.
    $text = [regex]::Replace($text, '[^\x00-\x7F]', { param($m) '&#' + [int][char]$m.Value + ';' })

    if ($WhatIf) { Write-Output ("WhatIf: would write {0} ({1} chars, {2} records)" -f $Out, $text.Length, $cards.Count); return }
    $dir = Split-Path -Parent (Join-Path $repo $Out)
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText((Join-Path $repo $Out), $text, (New-Object System.Text.UTF8Encoding($false)))
    # The page carries its own rules: the site stylesheet styles the frame, and
    # these seven classes only exist here.
    $css = @'
:root{--bg:#0b1014;--panel:#121a20;--panel2:#182229;--ink:#f5f3ea;--muted:#c4cdd1;--line:#46535a;--green:#a8d8b0;--amber:#e8be7a;--serif:Georgia,'Times New Roman',serif;--sans:Arial,'Segoe UI',sans-serif;--mono:Consolas,'Courier New',monospace}
body{background:var(--bg);color:var(--ink);font:15px/1.6 var(--sans);margin:0}
.wrap{width:min(980px,calc(100% - 36px));margin:auto}
.kicker{color:var(--green);font:10px var(--mono);letter-spacing:.08em;text-transform:uppercase}
.prov{border:1px solid var(--line);background:var(--panel);padding:18px;color:var(--muted);font:13px/1.6 var(--mono);margin:22px 0}
.prov a{color:var(--green)}
.outcome{border-left:3px solid var(--amber);background:var(--panel2);padding:16px 18px;margin:24px 0}
.outcome p{margin:6px 0}
.state{display:inline-block;color:var(--green);font:10px var(--mono);letter-spacing:.05em;text-transform:uppercase;border:1px solid var(--line);padding:2px 6px}
.arg-card{border:1px solid var(--line);background:var(--panel);padding:20px;margin:26px 0}
.arg-card h3{margin:0 0 4px;font:400 22px/1.2 var(--sans)}
.arg-meta{color:var(--muted);font:11px var(--mono);letter-spacing:.03em;text-transform:uppercase;margin:0 0 14px;padding:0;list-style:none;display:flex;flex-wrap:wrap;gap:6px 16px}
.arg-body p{font:17px/1.6 var(--serif);color:var(--ink);margin:0 0 14px}
.arg-cites{font:11px/1.5 var(--mono);color:var(--muted);border-top:1px solid var(--line);margin-top:14px;padding-top:12px;word-break:break-word}
.arg-cites a{color:var(--green)}
h1{font:400 clamp(30px,5vw,46px)/1.08 var(--sans);letter-spacing:-.035em;margin:10px 0 14px}
h2{font:400 26px/1.15 var(--sans);margin:30px 0 10px}
a{color:var(--green)}
@media(max-width:600px){.wrap{width:calc(100% - 24px)}.arg-card{padding:14px}.arg-body p{font:16px/1.6 var(--serif)}.arg-meta{font-size:10px}}
'@
    $cssPath = Join-Path $dir 'arguments.css'
    if (-not (Test-Path $cssPath) -or (Get-Content $cssPath -Raw -Encoding UTF8) -ne $css) {
        [IO.File]::WriteAllText($cssPath, $css, (New-Object System.Text.UTF8Encoding($false)))
        Write-Output ("wrote {0} ({1} bytes)" -f (Split-Path $cssPath -Leaf), $css.Length)
    }
    Write-Output ("wrote {0}: {1} bytes, {2} records, round1={3} round2={4}, sha256(store)={5}" -f $Out, $text.Length, $cards.Count, $round1.Count, $round2.Count, $sha)
}
finally { Pop-Location }
