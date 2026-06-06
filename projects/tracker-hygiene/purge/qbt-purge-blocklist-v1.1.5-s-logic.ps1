# ==============================================================================
# qbt-purge-blocklist-v1.1.5-s-logic.ps1  (fixed in place)
# ==============================================================================

param(
    [string]$QBHost = "http://127.0.0.1:8080",
    [string]$User = "admin",
    [string]$Pass = "BBQdeluxe",
    [string]$DomainBlocklistFile = "C:\Scripts\qbt-tracker-blocklist.txt",
    [string]$UrlBlocklistFile    = "C:\Scripts\qbt-tracker-blocklist-urls.txt",
    [switch]$DryRun
)

# ------------------------------------------------------------------------------
# Load blocklists
# ------------------------------------------------------------------------------
if (-not (Test-Path $DomainBlocklistFile)) { Write-Host "[ERROR] Missing domain blocklist."; exit 1 }
if (-not (Test-Path $UrlBlocklistFile))    { Write-Host "[ERROR] Missing URL blocklist."; exit 1 }

$BlockedDomains = Get-Content $DomainBlocklistFile | Where-Object { $_.Trim() -ne "" }
$BlockedUrls    = Get-Content $UrlBlocklistFile    | Where-Object { $_.Trim() -ne "" }

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

# ------------------------------------------------------------------------------
# Purge logic
# ------------------------------------------------------------------------------
foreach ($T in $Torrents) {

    $Trackers = Invoke-RestMethod "$QBHost/api/v2/torrents/trackers?hash=$($T.hash)" -WebSession $Session

    foreach ($Tr in $Trackers) {

        $url = ($Tr.url ?? "").Trim()
        if (-not $url) { continue }

        # Extract domain
        $domain = ""
        try { $domain = ([Uri]$url).Host } catch {
            if ($url -match "^(udp|http|https)://([^/:]+)") { $domain = $Matches[2] }
        }

        if (-not $domain) { continue }

        $matchDomain = $BlockedDomains -contains $domain
        $matchUrl    = $BlockedUrls    -contains $url

        if ($matchDomain -or $matchUrl) {

            if ($DryRun) {
                Write-Host "[DRYRUN] Would remove tracker from '$($T.name)': $url"
                continue
            }

            # Correct qBittorrent API parameter: urls=
            Invoke-RestMethod "$QBHost/api/v2/torrents/removeTrackers" `
                -Method POST `
                -Body @{
                    hash = $T.hash
                    urls = $url
                } `
                -WebSession $Session | Out-Null

            Write-Host "[REMOVED] $url"
        }
    }
}
