# ==============================================================================
# qbt-build-blocklist-v2.2.4.ps1
# ==============================================================================
# v2.2.4 — Performance fixes:
#   - Inlined InitDomain/InitUrl — eliminated per-row function call overhead
#   - Converted -contains array checks to HashSet.Contains() O(1) lookups
#   - Replaced InvalidAddress pattern loop with single joined regex match
# ==============================================================================

param(
    [string]$HarvestFile          = "C:\Scripts\qbt-tracker-harvest.csv",
    [string]$DomainBlocklistFile  = "C:\Scripts\qbt-tracker-blocklist.txt",
    [string]$UrlBlocklistFile     = "C:\Scripts\qbt-tracker-blocklist-urls.txt",
    [switch]$DryRun
)

if (-not (Test-Path $HarvestFile)) { Write-Host "[ERROR] Harvest file not found: $HarvestFile"; exit 1 }

$MinSamples = 50

# Pre-build HashSets for O(1) lookups in the hot loop
$EvidenceStateSet = [System.Collections.Generic.HashSet[string]]@(
    "forcedDL","downloading","stalledDL",
    "uploading","stalledUP","forcedUP"
)
$WorkingStatusSet = [System.Collections.Generic.HashSet[string]]@("2")
$DeadStatusSet    = [System.Collections.Generic.HashSet[string]]@("4")

# Single compiled regex for all invalid address patterns
$InvalidAddressRegex = [regex]::new(
    "no such host|not valid in its context|invalid address|invalid argument|name or service not known|host unreachable",
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)

Write-Host "[INFO] Loading harvest CSV..."
$rows = Import-Csv $HarvestFile
if ($rows -isnot [System.Collections.IList]) { $rows = @($rows) }
Write-Host "[INFO] Processing $($rows.Count) rows..."

$domainStats = @{}
$urlStats    = @{}

foreach ($r in $rows) {

    $url    = $r.URL
    $domain = $r.TrackerDomain
    if (-not $url) { continue }

    # --- Inline InitDomain ---
    if (-not $domainStats.ContainsKey($domain)) {
        $domainStats[$domain] = [PSCustomObject]@{
            Domain          = $domain
            TorrentHashes   = [System.Collections.Generic.HashSet[string]]::new()
            TotalSamples    = 0
            WorkingSamples  = 0
            DeadSamples     = 0
            EvidenceSamples = 0
            InvalidAddress  = $false
        }
    }
    $d = $domainStats[$domain]

    # --- Inline InitUrl ---
    if (-not $urlStats.ContainsKey($url)) {
        $urlStats[$url] = [PSCustomObject]@{
            URL             = $url
            Domain          = $domain
            TorrentHashes   = [System.Collections.Generic.HashSet[string]]::new()
            TotalSamples    = 0
            WorkingSamples  = 0
            DeadSamples     = 0
            EvidenceSamples = 0
            InvalidAddress  = $false
        }
    }
    $u = $urlStats[$url]

    $d.TotalSamples++
    $u.TotalSamples++

    if ($r.TorrentHash) {
        $null = $d.TorrentHashes.Add($r.TorrentHash)
        $null = $u.TorrentHashes.Add($r.TorrentHash)
    }

    # Single regex match instead of pattern loop
    if ($r.Message -and $InvalidAddressRegex.IsMatch($r.Message)) {
        $d.InvalidAddress = $true
        $u.InvalidAddress = $true
    }

    # HashSet lookups instead of -contains
    if ($WorkingStatusSet.Contains($r.Status)) {
        $d.WorkingSamples++
        $u.WorkingSamples++
    } elseif ($DeadStatusSet.Contains($r.Status)) {
        $d.DeadSamples++
        $u.DeadSamples++
    }

    if ($EvidenceStateSet.Contains($r.TorrentState)) {
        $d.EvidenceSamples++
        $u.EvidenceSamples++
    }
}

Write-Host "[INFO] Evaluating dead trackers..."

function DomainDead($d) {
    if ($d.InvalidAddress) { return $true }
    if ($d.EvidenceSamples -ge $MinSamples -and $d.WorkingSamples -eq 0 -and $d.DeadSamples -gt 0) { return $true }
    if ($d.TorrentHashes.Count -ge $MinSamples -and $d.WorkingSamples -eq 0 -and $d.DeadSamples -gt 0) { return $true }
    return $false
}

function UrlDead($u, $domainDead) {
    if ($domainDead) { return $true }
    if ($u.InvalidAddress) { return $true }
    if ($u.EvidenceSamples -ge $MinSamples -and $u.WorkingSamples -eq 0 -and $u.DeadSamples -gt 0) { return $true }
    if ($u.TorrentHashes.Count -ge $MinSamples -and $u.WorkingSamples -eq 0 -and $u.DeadSamples -gt 0) { return $true }
    return $false
}

$deadDomains = [System.Collections.Generic.HashSet[string]]::new()
$deadUrls    = [System.Collections.Generic.HashSet[string]]::new()

foreach ($kv in $domainStats.GetEnumerator()) {
    if (DomainDead $kv.Value) { $null = $deadDomains.Add($kv.Key) }
}

foreach ($kv in $urlStats.GetEnumerator()) {
    $u = $kv.Value
    $domainDead = $deadDomains.Contains($u.Domain)
    if (UrlDead $u $domainDead) { $null = $deadUrls.Add($u.URL) }
}

Write-Host "[INFO] Dead domains: $($deadDomains.Count)  Dead URLs: $($deadUrls.Count)"

if ($DryRun) {
    Write-Host "[DRYRUN] No files written."
} else {
    $deadDomains | Sort-Object | Set-Content $DomainBlocklistFile -Encoding UTF8
    $deadUrls    | Sort-Object | Set-Content $UrlBlocklistFile    -Encoding UTF8
    Write-Host "[DONE] Blocklists written."
}
