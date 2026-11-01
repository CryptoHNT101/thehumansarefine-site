# Generates editorial/approval-register.json from the articles on disk plus the
# approvals that are actually documented in the record.
#
# The point of this file is to make it impossible to infer an approval from a
# passing test. Every article carries the authority and date on which it was
# approved, the evidence for that approval, and the exact revision approved.
# Where no approval is documented, the field says so instead of guessing.
$ErrorActionPreference = 'Stop'
$repo = 'C:\Users\isaac\Documents\StarNet-Outputs\sprint'
$articlesDir = Join-Path $repo 'articles'

# Hash the CONTENT, not the checkout. On Windows with core.autocrlf=true the
# working tree holds CRLF while the git blob holds LF, so a raw file hash moves
# whenever git rewrites a file it has not otherwise changed. That produced a
# false "approved revision has drifted" on the first run of the verifier, on an
# article nobody had touched. The convention is recorded in the register so a
# reader can reproduce a hash independently.
$__sha = [System.Security.Cryptography.SHA256]::Create()
function Get-NormalizedSha256([string]$path) {
    $text = [IO.File]::ReadAllText($path)
    $text = $text -replace "`r`n", "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    return ([BitConverter]::ToString($__sha.ComputeHash($bytes))).Replace('-', '').ToLower()
}

# Approvals documented in the Commander's own words. Quoted so they can be
# checked against the transcript rather than taken on trust.
$approvals = @{
    'wall-street-ai-bet' = @{
        authority = 'Commander (owner)'
        date      = '2026-11-01'
        evidence  = 'Commander editorial publication sprint: "The Commander has personally reviewed and APPROVED FOR PUBLICATION the Wall Street AI investigation. Publish it as the main lead story on the homepage."'
    }
    'ecb-ai-adoption-europe' = @{
        authority = 'Commander (owner)'
        date      = '2026-10-31'
        evidence  = 'Commander editorial approval: "Commander has reviewed and approved the following four articles for publication: 1. ECB - AI Adoption in Europe"'
    }
    'uk-planning-ai-planassist' = @{
        authority = 'Commander (owner)'
        date      = '2026-10-31'
        evidence  = 'Commander editorial approval: "2. UK - DeepMind Planning AI"'
    }
    'aisi-protein-filtering' = @{
        authority = 'Commander (owner)'
        date      = '2026-10-31'
        evidence  = 'Commander editorial approval: "3. AISI - AI Protein Filtering"'
    }
    'ico-ai-developers-data-protection' = @{
        authority = 'Commander (owner)'
        date      = '2026-10-31'
        evidence  = 'Commander editorial approval: "4. ICO - AI Developers and Data Protection"'
    }
}

$items = @()
foreach ($f in @(Get-ChildItem $articlesDir -Filter '*.html' | Where-Object { $_.Name -notlike '*-evidence.html' } | Sort-Object Name)) {
    $slug = $f.BaseName
    $h = [IO.File]::ReadAllText($f.FullName)
    $headline = [System.Net.WebUtility]::HtmlDecode(([regex]::Match($h, '(?is)<h1[^>]*>(.*?)</h1>').Groups[1].Value -replace '<[^>]+>', '' -replace '\s+', ' ').Trim())
    $sha = Get-NormalizedSha256 $f.FullName
    $pub = [regex]::Match($h, '<meta\s+property="article:published_time"\s+content="([^"]+)"').Groups[1].Value
    $canonical = [regex]::Match($h, '<link\s+rel="canonical"\s+href="([^"]+)"').Groups[1].Value

    $a = $approvals[$slug]
    if ($a) {
        $status = 'APPROVED - PUBLISHED'
        $authority = $a.authority; $date = $a.date; $evidence = $a.evidence
    } else {
        $status = 'PUBLISHED - APPROVAL NOT RECORDED'
        $authority = 'UNRECORDED'
        $date = $null
        $evidence = 'Published before this register existed. No approval record is available on this station. Recorded as unrecorded rather than reconstructed from the fact of publication.'
    }

    $items += [pscustomobject][ordered]@{
        slug           = $slug
        headline       = $headline
        status         = $status
        approvingParty = $authority
        approvalDate   = $date
        approvalEvidence = $evidence
        revision       = @{ algorithm = 'sha256'; of = 'articles/' + $slug + '.html'; contentNormalisation = 'CRLF->LF then UTF-8'; hash = $sha }
        publishedAt    = $pub
        canonicalUrl   = $canonical
    }
}

$register = [ordered]@{
    register      = 'THE HUMANS ARE FINE - editorial approval register'
    purpose       = 'Canonical record of who authorized each story, when, and which revision was authorized. A passing automated test is not an approval and must never be recorded here as one.'
    generatedAt   = (Get-Date).ToString('o')
    generatedBy   = 'scripts\build-approval-register.ps1'
    rule          = 'An article may be published only when a row here shows status APPROVED - PUBLISHED with a named approving party, a date and verbatim evidence, and the recorded revision hash still matches the article content.'
    hashConvention = 'sha256 over the article content with CRLF normalised to LF and encoded UTF-8, so the hash does not depend on git line-ending settings.'
    publishedCount = $items.Count
    articles      = $items
}

$outDir = Join-Path $repo 'editorial'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$out = Join-Path $outDir 'approval-register.json'
($register | ConvertTo-Json -Depth 8) | Set-Content -Path $out -Encoding UTF8
Write-Output "wrote $out with $($items.Count) rows"
$rec = @($items | Where-Object { $_.status -eq 'APPROVED - PUBLISHED' }).Count
$unr = @($items | Where-Object { $_.status -ne 'APPROVED - PUBLISHED' }).Count
Write-Output "  approved with recorded evidence: $rec"
Write-Output "  published but approval not recorded: $unr"
