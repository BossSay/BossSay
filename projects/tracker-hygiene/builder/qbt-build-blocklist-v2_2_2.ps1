# ==============================================================================
# qbt-build-blocklist-v2.2.2.ps1  (fixed in place)
# ==============================================================================

param(
    [string]$HarvestFile = "C:\Scripts\qbt-tracker-harvest.csv",
    [string]$DomainBlocklistFile = "C:\Scripts\qbt-tracker-blocklist.txt",
    [string]$UrlBlocklistFile    = "C:\Scripts\qbt-tracker-blocklist-urls.txt",
    [switch]$DryRun
)

if (-not (Test-Path $HarvestFile)) { exit 1 }

$MinSamples = 5

$EvidenceStates = @(
    "forcedDL","downloading","stalledDL",
    "uploading","stalledUP","forcedUP"
)

$WorkingStatuses = @("2")        # qBittorrent status 2 = Working
$DeadStatuses    = @("4")        # qBittorrent status 4 = Not working

$InvalidAddressPatterns = @(
    "no such host","not valid in its context","invalid address",
    "invalid argument","name or service not known","host unreachable"
)

$rows = Import-Csv $HarvestFile
if ($rows -isnot [System.Collections.IList]) { $rows = @($rows) }

$domainStats = @{}
$urlStats    = @{}

function InitDomain($d) {
    if (-not $domainStats.ContainsKey($d)) {
        $domainStats[$d] = [PSCustomObject]@{
            Domain          = $d
            TorrentHashes   = [System.Collections.Generic.HashSet[string]]::new()
            TotalSamples    = 0
            WorkingSamples  = 0
            DeadSamples     = 0
            EvidenceSamples = 0
            InvalidAddress  = $false
        }
    }
    return $domainStats[$d]
}

function InitUrl($u,$d) {
    if (-not $urlStats.ContainsKey($u)) {
        $urlStats[$u] = [PSCustomObject]@{
            URL             = $u
            Domain          = $d
            TorrentHashes   = [System.Collections.Generic.HashSet[string]]::new()
            TotalSamples    = 0
            WorkingSamples  = 0
            DeadSamples     = 0
            EvidenceSamples = 0
            InvalidAddress  = $false
        }
    }
    return $urlStats[$u]
}

foreach ($r in $rows) {

    $url     = $r.URL
    $domain  = $r.TrackerDomain
    if (-not $url) { continue }

    $d = InitDomain $domain
    $u = InitUrl    $url $domain

    $d.TotalSamples++
    $u.TotalSamples++

    if ($r.TorrentHash) {
        $null = $d.TorrentHashes.Add($r.TorrentHash)
        $null = $u.TorrentHashes.Add($r.TorrentHash)
    }

    if ($r.Message) {
        $lower = $r.Message.ToLowerInvariant()
        foreach ($pat in $InvalidAddressPatterns) {
            if ($lower.Contains($pat)) {
                $d.InvalidAddress = $true
                $u.InvalidAddress = $true
            }
        }
    }

    $isWorking = $WorkingStatuses -contains $r.Status
    $isDead    = $DeadStatuses    -contains $r.Status

    if ($isWorking) {
        $d.WorkingSamples++
        $u.WorkingSamples++
    } elseif ($isDead) {
        $d.DeadSamples++
        $u.DeadSamples++
    }

    if ($EvidenceStates -contains $r.TorrentState) {
        $d.EvidenceSamples++
        $u.EvidenceSamples++
    }
}

function DomainDead($d) {
    if ($d.InvalidAddress) { return $true }
    if ($d.EvidenceSamples -gt 0 -and $d.WorkingSamples -eq 0 -and $d.DeadSamples -gt 0) { return $true }
    if ($d.TorrentHashes.Count -ge $MinSamples -and $d.WorkingSamples -eq 0 -and $d.DeadSamples -gt 0) { return $true }
    return $false
}

function UrlDead($u,$domainDead) {
    if ($domainDead) { return $true }
    if ($u.InvalidAddress) { return $true }
    if ($u.EvidenceSamples -gt 0 -and $u.WorkingSamples -eq 0 -and $u.DeadSamples -gt 0) { return $true }
    if ($u.TorrentHashes.Count -ge $MinSamples -and $u.WorkingSamples -eq 0 -and $u.DeadSamples -gt 0) { return $true }
    return $false
}

$deadDomains = New-Object System.Collections.Generic.HashSet[string]
$deadUrls    = New-Object System.Collections.Generic.HashSet[string]

foreach ($kv in $domainStats.GetEnumerator()) {
    if (DomainDead $kv.Value) { $null = $deadDomains.Add($kv.Key) }
}

foreach ($kv in $urlStats.GetEnumerator()) {
    $u = $kv.Value
    $domainDead = $deadDomains.Contains($u.Domain)
    if (UrlDead $u $domainDead) { $null = $deadUrls.Add($u.URL) }
}

if (-not $DryRun) {
    $deadDomains | Sort-Object | Set-Content $DomainBlocklistFile -Encoding UTF8
    $deadUrls    | Sort-Object | Set-Content $UrlBlocklistFile    -Encoding UTF8
}
