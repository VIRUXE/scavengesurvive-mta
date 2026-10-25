# Sends one command to the running server through the dev resource's HTTP export (MTA has no RCON).
#   pwsh server-config/rcon.ps1 help
#   pwsh server-config/rcon.ps1 rr items
#   pwsh server-config/rcon.ps1 cmd Bob additem M9Pistol
#   pwsh server-config/rcon.ps1 lua return getPlayerCount()
#   pwsh server-config/rcon.ps1 -Prod players
# Credentials come from local.settings.xml (*dev.http_user / *dev.http_pass); -Prod targets nasa on the LAN with
# prod.settings.xml (git-ignored, same two settings). Prints the output lines; exit 1 on ok=false.
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Command,
    [string]$Url = "http://127.0.0.1:22005",
    [string]$Settings = (Join-Path $PSScriptRoot "local.settings.xml"),
    [switch]$Prod
)
$ErrorActionPreference = "Stop"
if ($Prod) {
    $Url = "http://192.168.1.100:22005"
    $Settings = Join-Path $PSScriptRoot "prod.settings.xml"
}
if (-not $Command) { $Command = @("help") }
$xml = [xml](Get-Content -LiteralPath $Settings -Raw)
$user = ($xml.settings.setting | Where-Object { $_.name -eq "*dev.http_user" }).value
$pass = ($xml.settings.setting | Where-Object { $_.name -eq "*dev.http_pass" }).value
if (-not $user -or -not $pass) { throw "*dev.http_user / *dev.http_pass are not set in $Settings (run-local.ps1 fills them in)" }
$cred = [pscredential]::new($user, (ConvertTo-SecureString $pass -AsPlainText -Force))
$body = ConvertTo-Json -Compress -InputObject @(, ($Command -join " "))
try {
    $r = Invoke-RestMethod -Uri "$Url/dev/call/rcon" -Method Post -Body $body -ContentType "application/json" `
        -Credential $cred -Authentication Basic -AllowUnencryptedAuthentication
} catch {
    throw "rcon request failed: $($_.Exception.Message) (is the server up with the dev resource started?)"
}
$res = if ($r -is [array]) { $r[0] } else { $r }
foreach ($line in @($res.output)) { $line }
if (-not $res.ok) { exit 1 }
