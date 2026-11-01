# ============================================================================
# THE HUMANS ARE FINE - local static server
#
# Serves the repository as the site will be served: real paths, real 404s,
# correct content types. Used to verify the release candidate before it is
# pushed, because "the links are correct in the source" and "the links resolve
# over HTTP" are different claims and only the second one matters.
#
# Deliberately not a framework and not a build step. GET and HEAD only, no
# directory listing, no traversal, no caching headers that would hide a
# regeneration.
#
#   pwsh -File scripts/thaf-serve-local.ps1 -Port 8321
# ============================================================================
param(
    [int]$Port = 8321,
    [string]$Root = ''
)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$Root = (Resolve-Path $Root).Path

$types = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.xml'  = 'application/xml; charset=utf-8'
    '.txt'  = 'text/plain; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.svg'  = 'image/svg+xml'
    '.pdf'  = 'application/pdf'
    '.ico'  = 'image/x-icon'
    '.woff2' = 'font/woff2'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
Write-Output "serving $Root on http://127.0.0.1:$Port/"
try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $res = $ctx.Response
        try {
            $rel = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath).TrimStart('/')
            if ($rel -eq '') { $rel = 'index.html' }
            if ($rel.EndsWith('/')) { $rel = $rel + 'index.html' }

            $full = Join-Path $Root ($rel -replace '/', '\')
            $fullResolved = $null
            try { $fullResolved = (Resolve-Path $full -ErrorAction Stop).Path } catch { }

            # Traversal guard: a resolved path outside the root is a 404, not a file.
            $served = $false
            if ($fullResolved -and $fullResolved.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path $fullResolved -PathType Leaf)) {
                $bytes = [System.IO.File]::ReadAllBytes($fullResolved)
                $ext = [System.IO.Path]::GetExtension($fullResolved).ToLowerInvariant()
                $res.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
                $res.StatusCode = 200
                $res.ContentLength64 = $bytes.Length
                if ($req.HttpMethod -ne 'HEAD') { $res.OutputStream.Write($bytes, 0, $bytes.Length) }
                $served = $true
            }

            if (-not $served) {
                $res.StatusCode = 404
                $body = [System.Text.Encoding]::UTF8.GetBytes('<!doctype html><title>404</title><h1>404</h1><p>Not found.</p>')
                $res.ContentType = 'text/html; charset=utf-8'
                $res.ContentLength64 = $body.Length
                if ($req.HttpMethod -ne 'HEAD') { $res.OutputStream.Write($body, 0, $body.Length) }
            }
        } catch {
            try { $res.StatusCode = 500 } catch { }
        } finally {
            try { $res.OutputStream.Close() } catch { }
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
