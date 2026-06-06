# ==============================================================================
# QBT-TRACKER-HARVESTER-v2.2.1.ps1  (fixed in place)
# ==============================================================================

$QBHost     = "http://127.0.0.1:8080"
$User       = "admin"
$Pass       = "BBQdeluxe"
$OutputFile = "C:\Scripts\qbt-tracker-harvest.csv"
$StateFile  = "C:\Scripts\qbt-tracker-harvest.state"
$Delay      = 200

$EvidenceStates = @(
    "forcedDL","downloading","stalledDL",
    "uploading","stalledUP","forcedUP"
)

$Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
Invoke-RestMethod "$QBHost/api/v2/auth/login" -Method POST -Body "username=$User&password=$Pass" -WebSession $Session | Out-Null

$AllTorrents = Invoke-RestMethod "$QBHost/api/v2/torrents/info" -WebSession $Session
$Torrents    = $AllTorrents | Where-Object { $_.state -in $EvidenceStates }

$Processed  = @{}
$StartIndex = 0
$Rows       = @()

if (Test-Path $StateFile) {
    $State = Get-Content $StateFile | ConvertFrom-Json
    $StartIndex = $State.StartIndex
    foreach ($h in $State.Processed) { $Processed[$h] = $true }

    if (Test-Path $OutputFile) {
        $Rows = Import-Csv $OutputFile
        if ($Rows -isnot [System.Collections.IList]) { $Rows = @($Rows) }
    }
}

function Get-TrackerDomain($url) {
    if ([string]::IsNullOrWhiteSpace($url)) { return "" }
    try { return ([Uri]$url).Host }
    catch {
        if ($url -match "^(udp|http|https)://([^/:]+)") { return $Matches[2] }
        return $url
    }
}

for ($i = $StartIndex; $i -lt $Torrents.Count; $i++) {

    $T = $Torrents[$i]
    if ($Processed.ContainsKey($T.hash)) { continue }

    try {
        $Trackers = Invoke-RestMethod "$QBHost/api/v2/torrents/trackers?hash=$($T.hash)" -WebSession $Session

        foreach ($Tr in $Trackers) {
            $url = ($Tr.url ?? "").Trim()
            if (-not $url) { continue }

            $Rows += [PSCustomObject]@{
                URL           = $url
                TrackerDomain = Get-TrackerDomain $url
                TorrentHash   = $T.hash
                TorrentName   = $T.name
                TorrentState  = $T.state
                Status        = $Tr.status
                Peers         = $Tr.num_peers
                Seeds         = $Tr.num_seeds
                Leeches       = $Tr.num_leeches
                Message       = $Tr.msg
            }
        }

        $Processed[$T.hash] = $true

    } catch {
        @{ StartIndex = $i; Processed = @($Processed.Keys) } |
            ConvertTo-Json -Depth 5 | Set-Content $StateFile
        $Rows | Export-Csv $OutputFile -NoTypeInformation -Encoding UTF8
        exit
    }

    if ($i % 25 -eq 0) {
        @{ StartIndex = $i; Processed = @($Processed.Keys) } |
            ConvertTo-Json -Depth 5 | Set-Content $StateFile
        $Rows | Export-Csv $OutputFile -NoTypeInformation -Encoding UTF8
    }

    Start-Sleep -Milliseconds $Delay
}

$Rows | Export-Csv $OutputFile -NoTypeInformation -Encoding UTF8
Remove-Item $StateFile -ErrorAction SilentlyContinue
