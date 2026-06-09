# ==============================================================================
# qbt-purge-blocklist-v1.1.6.ps1
# ==============================================================================
# v1.1.6 — Performance fix:
#   - Batches all tracker removals per torrent into a single API call
#     instead of one call per tracker URL (was N calls per torrent)
# ==============================================================================

param(
    [string]$QBHost               = "http://127.0.0.1:8080",
    [string]$User                 = "admin",
    [string]$Pass                 = "BBQdeluxe",
    [string]$DomainBlocklistFile  = "C:\Scripts\qbt-tracker-blocklist.txt",
    [string]$UrlBlocklistFile     = "C:\Scripts\qbt-tracker-blocklist-urls.txt",
    [switch]$DryRun
)

# ------------------------------------------------------------------------------
# Load blocklists
# ------------------------------------------------------------------------------
if (-not (Test-Path $DomainBlocklistFile)) { Write-Host "[ERROR] Missing domain blocklist."; exit 1 }
if (-not (Test-Path $UrlBlocklistFile))    { Write-Host "[ERROR] Missing URL blocklist."; exit 1 }

$BlockedDomains = [System.Collections.Generic.HashSet[string]]@(
    Get-Content $DomainBlocklistFile | Where-Object { $_.Trim() -ne "" }
)
$BlockedUrls = [System.Collections.Generic.HashSet[string]]@(
    Get-Content $UrlBlocklistFile | Where-Object { $_.Trim() -ne "" }
)

Write-Host "[INFO] Loaded $($BlockedDomains.Count) blocked domains."
Write-Host "[INFO] Loaded $($BlockedUrls.Count) blocked URLs."

# ------------------------------------------------------------------------------
# Login
# ------------------------------------------------------------------------------
$Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
Invoke-RestMethod "$QBHost/api/v2/auth/login" `
    -Method POST `
    -Body "username=$User&password=$Pass" `
    -WebSession $Session | Out-Null

# ------------------------------------------------------------------------------
# Fetch all torrents
# ------------------------------------------------------------------------------
$Torrents = Invoke-RestMethod "$QBHost/api/v2/torrents/info" -WebSession $Session
Write-Host "[INFO] Processing $($Torrents.Count) torrents..."

# ------------------------------------------------------------------------------
# Purge logic — batched per torrent
# ------------------------------------------------------------------------------
foreach ($T in $Torrents) {

    $Trackers = Invoke-RestMethod "$QBHost/api/v2/torrents/trackers?hash=$($T.hash)" -WebSession $Session

    $toRemove = [System.Collections.Generic.List[string]]::new()

    foreach ($Tr in $Trackers) {

        $url = ($Tr.url ?? "").Trim()
        if (-not $url) { continue }

        # Extract domain
        $domain = ""
        try { $domain = ([Uri]$url).Host } catch {
            if ($url -match "^(udp|http|https)://([^/:]+)") { $domain = $Matches[2] }
        }
        if (-not $domain) { continue }

        if ($BlockedDomains.Contains($domain) -or $BlockedUrls.Contains($url)) {
            $null = $toRemove.Add($url)
        }
    }

    if ($toRemove.Count -gt 0) {
        if ($DryRun) {
            foreach ($url in $toRemove) {
                Write-Host "[DRYRUN] Would remove from '$($T.name)': $url"
            }
        } else {
            # Single API call per torrent for all matched URLs
            Invoke-RestMethod "$QBHost/api/v2/torrents/removeTrackers" `
                -Method POST `
                -Body @{
                    hash = $T.hash
                    urls = ($toRemove -join "|")
                } `
                -WebSession $Session | Out-Null

            foreach ($url in $toRemove) {
                Write-Host "[REMOVED] $url"
            }
        }
    }
}

Write-Host "[DONE]"
