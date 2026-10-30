# thaf-trust-2026-10-30.ps1 - Day Shift 8 transparency patch.
#
# What it changes, and nothing else:
#   1. Every article's FOR HUMAN CONSUMPTION block gets a one-line legend saying what the block is
#      (commentary, in the newsroom's own voice) and is not (reporting, a source).
#   2. Every "Corrections" link that pointed at the top of the Standards page now lands on the
#      page's #corrections section, which previously had no id at all.
#   3. The Standards page gains a #corrections anchor and a short Correction log listing the one
#      dated notice currently attached to an article, linked to the notice itself.
#
# It does not touch a single sentence of reporting, any date, any evidence file, or any claim.
# Re-running is a no-op: every change is guarded by its own marker.
#
#   -Verify   report what would change, write nothing
param([switch]$Verify)

$ErrorActionPreference = 'Stop'
$site = Split-Path -Parent $PSScriptRoot
$slugs = @(
    'alignment-auditors-false-positives', 'anthropic-auto-mode-monitors', 'anthropic-s1-operating-profit',
    'claude-mythos-5-aisi-incident', 'genie-4-world-model', 'gpt-6-1-terra-critical',
    'graft-localizing-cheating', 'metr-openai-agent-monitoring', 'vos-chatbots-court-claims'
)

$legend = '<p class="hfc-note">Commentary and a plain-language summary, written in the newsroom&rsquo;s own voice. It is not reporting, it introduces no source, and it should not be quoted as a finding.</p>'

$logBlock = @'
<h3 id="correction-log">Correction log</h3>
<p>Corrections are attached to the article they concern, and every article's revision history sits in its Evidence File. This is the index of dated notices currently attached, newest first.</p>
<table class="correction-log">
<thead><tr><th scope="col">Date</th><th scope="col">Label</th><th scope="col">Article</th><th scope="col">What changed</th></tr></thead>
<tbody>
<tr>
<td>27 October 2026</td>
<td>Clarification</td>
<td><a href="../articles/anthropic-auto-mode-monitors.html#clarification-2026-10-27">Anthropic Auto Mode: automated monitors</a></td>
<td>An earlier version described the tested monitors as Claude Code&rsquo;s Auto Mode and &ldquo;an approximation of OpenAI Codex&rsquo;s Guardian&rdquo;. The paper&rsquo;s Table&nbsp;2 calls the Guardian variant &ldquo;An approximation of Codex&rsquo;s production default&rdquo;. The article now states that relationship accurately. No experimental statistic changed. <a href="../articles/anthropic-auto-mode-monitors.html#clarification-2026-10-27">Read the notice</a>.</td>
</tr>
</tbody>
</table>
<p class="log-note">If a notice you are expecting is missing from this index, that is a fault and worth reporting to <a href="mailto:contact@thehumansarefine.com">contact@thehumansarefine.com</a>.</p>
'@

$changed = @()

# ---------- 1. articles ----------
foreach ($s in $slugs) {
    $path = Join-Path $site "articles\$s.html"
    $t = [IO.File]::ReadAllText($path)
    $orig = $t
    $notes = @()

    if ($t -notmatch 'class="hfc-note"') {
        $titleRx = '<h2 class="hfc-title" id="hfc-title">FOR HUMAN CONSUMPTION</h2>'
        if ($t -notmatch [regex]::Escape($titleRx)) { throw "no hfc title in $s" }
        $t = $t.Replace($titleRx, $titleRx + "`r`n" + $legend)
        $notes += 'legend'
    }

    $corrA = 'data-thaf-event="corrections_open" href="../standards/index.html"'
    $corrB = 'data-thaf-event="corrections_open" href="../standards/index.html#corrections"'
    $n = ([regex]::Matches($t, [regex]::Escape($corrA))).Count
    if ($n -gt 0) { $t = $t.Replace($corrA, $corrB); $notes += ("corrections-anchor x$n") }

    if ($t -ne $orig) {
        $changed += "$s : $($notes -join ', ')"
        if (-not $Verify) { [IO.File]::WriteAllText($path, $t) }
    }
}

# ---------- 2. standards page ----------
$sp = Join-Path $site 'standards\index.html'
$st = [IO.File]::ReadAllText($sp)
$so = $st
$snotes = @()

if ($st -notmatch 'id="corrections"') {
    $m = [regex]::Match($st, '(?s)<h2>\s*Corrections\s*</h2>')
    if (-not $m.Success) { throw 'standards: Corrections heading not found' }
    $st = $st.Remove($m.Index, $m.Length).Insert($m.Index, '<h2 id="corrections">Corrections</h2>')
    $snotes += 'anchor'
}

if ($st -notmatch 'id="correction-log"') {
    $anchor = '<h2>Editorial standards</h2>'
    $i = $st.IndexOf($anchor)
    if ($i -lt 0) { throw 'standards: Editorial standards heading not found' }
    $st = $st.Insert($i, $logBlock + "`r`n")
    $snotes += 'log'
}

if ($st -ne $so) {
    $changed += "standards/index.html : $($snotes -join ', ')"
    if (-not $Verify) { [IO.File]::WriteAllText($sp, $st) }
}

# ---------- 3. stylesheet ----------
$cp = Join-Path $site 'assets\article.css'
$css = [IO.File]::ReadAllText($cp)
if ($css -notmatch '\.hfc \.hfc-note') {
    $css += @'

/* Day Shift 8: what the FOR HUMAN CONSUMPTION block is, and is not. */
.hfc .hfc-note{
  margin:0 0 1rem;
  font-size:.82rem;
  letter-spacing:.02em;
  text-transform:none;
  color:var(--muted, #6b6b6b);
  border-left:3px solid var(--amber, #d99a2b);
  padding-left:.7rem;
}
'@
    $changed += 'assets/article.css : hfc-note rule'
    if (-not $Verify) { [IO.File]::WriteAllText($cp, $css) }
}

if ($changed.Count -eq 0) { 'no changes needed (patch already applied)' }
else { $changed }
