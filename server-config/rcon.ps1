# Sends one command to the running server through the dev resource's HTTP export (MTA has no RCON).
#   pwsh server-config/rcon.ps1 help
#   pwsh server-config/rcon.ps1 rr items
#   pwsh server-config/rcon.ps1 cmd Bob additem M9Pistol
#   pwsh server-config/rcon.ps1 lua return getPlayerCount()
#   pwsh server-config/rcon.ps1 -Prod players
# Credentials come from local.settings.xml (*dev.http_user / *dev.http_pass). -Prod runs the request on nasa over ssh
# against 127.0.0.1, the only address prod's serial check lets the rcon account in from; its password never leaves
# nasa. Prints the output lines; exit 1 on ok=false.
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Command,
    [string]$Url = "http://127.0.0.1:22005",
    [string]$Settings = (Join-Path $PSScriptRoot "local.settings.xml"),
    [switch]$Prod
)
$ErrorActionPreference = "Stop"
if (-not $Command) { $Command = @("help") }
$body = ConvertTo-Json -Compress -InputObject @(, ($Command -join " "))
if ($Prod) {
    $remote = 'D=/gta/sa/mta/servers/scavengesurvive/mods/deathmatch; ' +
        'P=$(grep -oP ''\*dev\.http_pass" value="\K[^"]*'' $D/settings.xml); ' +
        'curl -sf -u "rcon:$P" -H "Content-Type: application/json" --data-binary @- http://127.0.0.1:22005/dev/call/rcon'
    $json = $body | ssh -o BatchMode=yes nasa $remote
    if ($LASTEXITCODE -ne 0) { throw "rcon request on nasa failed (ssh/curl exit $LASTEXITCODE; is the server up with the dev resource started?)" }
    $r = $json | ConvertFrom-Json
} else {
    $xml = [xml](Get-Content -LiteralPath $Settings -Raw)
    $user = ($xml.settings.setting | Where-Object { $_.name -eq "*dev.http_user" }).value
    $pass = ($xml.settings.setting | Where-Object { $_.name -eq "*dev.http_pass" }).value
    if (-not $user -or -not $pass) { throw "*dev.http_user / *dev.http_pass are not set in $Settings (run-local.ps1 fills them in)" }
    $cred = [pscredential]::new($user, (ConvertTo-SecureString $pass -AsPlainText -Force))
    try {
        $r = Invoke-RestMethod -Uri "$Url/dev/call/rcon" -Method Post -Body $body -ContentType "application/json" `
            -Credential $cred -Authentication Basic -AllowUnencryptedAuthentication
    } catch {
        throw "rcon request failed: $($_.Exception.Message) (is the server up with the dev resource started?)"
    }
}
$res = if ($r -is [array]) { $r[0] } else { $r }
foreach ($line in @($res.output)) { $line }
if (-not $res.ok) { exit 1 }
