# Prepares the local MTA server for this repo and starts it. Safe to run any number of times.
[CmdletBinding()]
param(
    [string]$MtaServer = "C:\Program Files (x86)\MTA San Andreas 1.6\server",
    [string]$MariaDb = "C:\Program Files\MariaDB 12.2\bin\mariadb.exe",
    [string]$DbUser = "root",
    [string]$DbPassword = "",
    [string]$DbName = "scavengesurvive",
    [switch]$Reset,
    [switch]$NoStart
)
$ErrorActionPreference = "Stop"
$Repo = Split-Path $PSScriptRoot -Parent
$Dm = Join-Path $MtaServer "mods\deathmatch"
if (-not (Test-Path -LiteralPath (Join-Path $Dm "mtaserver.conf"))) { throw "No MTA server at $MtaServer" }
if (Get-Process -Name "MTA Server" -ErrorAction SilentlyContinue) { throw "MTA Server is running; stop it first (type 'shutdown' in its console)." }
$Utf8 = [Text.UTF8Encoding]::new($false)

# (a) database: create, migrate, procedures, events, seeds
$sqlArgs = @("-m", "tools.sqltool", "--db", $DbName, "--user", $DbUser)
if ($DbPassword) { $sqlArgs += @("--password", $DbPassword) }
if ($Reset) { $sqlArgs += "--reset" }
Push-Location $Repo
try { & python @sqlArgs "apply"; if ($LASTEXITCODE -ne 0) { throw "sqltool failed ($LASTEXITCODE)" } } finally { Pop-Location }

# (b) the despawn/cleanup events in sql/events need the scheduler
$dbAuth = @("-u", $DbUser)
if ($DbPassword) { $dbAuth += "--password=$DbPassword" }
& $MariaDb @dbAuth -e "SET GLOBAL event_scheduler = ON;"
if ($LASTEXITCODE -ne 0) { throw "mariadb failed ($LASTEXITCODE)" }

# (c) settings.xml (server-wide registry; overrides lib's meta.xml defaults)
$local = Join-Path $PSScriptRoot "local.settings.xml"
if (-not (Test-Path -LiteralPath $local)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "local.settings.example.xml") -Destination $local
    Write-Host "Created $local from the example; edit it if your DB needs a password."
}
Copy-Item -LiteralPath $local -Destination (Join-Path $Dm "settings.xml") -Force

# (d) mtaserver.conf, always regenerated from the untouched stock copy
$conf = Join-Path $Dm "mtaserver.conf"
$stock = "$conf.stock"
if (-not (Test-Path -LiteralPath $stock)) { Copy-Item -LiteralPath $conf -Destination $stock }
$text = [IO.File]::ReadAllText($stock)
$text = [regex]::Replace($text, '(?m)^[ \t]*<resource\s[^>]*/>[ \t]*\r?\n', '')
$ours = (Get-Content -LiteralPath (Join-Path $PSScriptRoot "resources.xml") | Where-Object { $_ -match '^\s*<resource\s' }) -join "`r`n"
$text = [regex]::Replace($text, '(?m)^</config>', { param($m) $ours + "`r`n" + $m.Value })
function Set-ConfValue([string]$Text, [string]$Tag, [string]$Value) {
    $pattern = "(?m)^([ \t]*<$Tag>)[^<]*(</$Tag>)"
    if (-not [regex]::IsMatch($Text, $pattern)) { throw "mtaserver.conf has no <$Tag>" }
    return [regex]::Replace($Text, $pattern, { param($m) $m.Groups[1].Value + $Value + $m.Groups[2].Value })
}
$text = Set-ConfValue $text "elementdata_whitelisted" "1"
$text = Set-ConfValue $text "fpslimit" "60"
$text = Set-ConfValue $text "scriptdebugloglevel" "3"
$text = Set-ConfValue $text "servername" "Scavenge and Survive (dev)"
[IO.File]::WriteAllText($conf, $text, $Utf8)

# (e) junction the resource group into the server
$link = Join-Path $Dm "resources\[scavengesurvive]"
$target = Join-Path $Repo "resources\[scavengesurvive]"
if (Test-Path -LiteralPath $link) {
    $item = Get-Item -LiteralPath $link
    if ($item.LinkType -ne "Junction" -or ($item.Target | Select-Object -First 1) -ne $target) {
        throw "$link exists and is not a junction to $target; remove it by hand."
    }
} else {
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
}

# (f) ACL: our resources may call loadstring (lib modules; the stock Default ACL denies it); dev may call restartResource.
# Edited with the XML parser because the server re-saves acl.xml in its own format; the ScavengeSurvive group and ACL
# are removed and rebuilt from resources.xml on every run.
$acl = Join-Path $Dm "acl.xml"
if (-not (Test-Path -LiteralPath "$acl.stock")) { Copy-Item -LiteralPath $acl -Destination "$acl.stock" }
$aclOld = [IO.File]::ReadAllText($acl)
$doc = [xml]::new()
$doc.LoadXml($aclOld)
$root = $doc.DocumentElement
function New-AclElement([string]$Tag, [Collections.IDictionary]$Attrs) {
    $e = $doc.CreateElement($Tag)
    foreach ($k in $Attrs.Keys) { $e.SetAttribute($k, $Attrs[$k]) }
    $e.IsEmpty = $false # <x></x>, as the server writes it
    return $e
}
foreach ($node in @($root.SelectNodes('group[@name="ScavengeSurvive"] | acl[@name="ScavengeSurvive"]'))) { [void]$root.RemoveChild($node) }
$names = ([xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot "resources.xml") -Raw)).resources.resource | ForEach-Object { $_.src }
$group = New-AclElement "group" ([ordered]@{ name = "ScavengeSurvive" })
[void]$group.AppendChild((New-AclElement "acl" ([ordered]@{ name = "ScavengeSurvive" })))
foreach ($n in $names) { [void]$group.AppendChild((New-AclElement "object" ([ordered]@{ name = "resource.$n" }))) }
$ssAcl = New-AclElement "acl" ([ordered]@{ name = "ScavengeSurvive" })
[void]$ssAcl.AppendChild((New-AclElement "right" ([ordered]@{ name = "function.loadstring"; access = "true" })))
$default = $root.SelectSingleNode('acl[@name="Default"]')
if (-not $default) { throw "acl.xml has no Default ACL" }
[void]$root.InsertBefore($group, $default)
[void]$root.InsertBefore($ssAcl, $default)
$admin = $root.SelectSingleNode('group[@name="Admin"]')
if (-not $admin) { throw "acl.xml has no Admin group" }
if (-not $admin.SelectSingleNode('object[@name="resource.dev"]')) {
    [void]$admin.AppendChild((New-AclElement "object" ([ordered]@{ name = "resource.dev" })))
}
$ws = [Xml.XmlWriterSettings]::new()
$ws.Indent = $true
$ws.IndentChars = "    "
$ws.NewLineChars = if ($aclOld.Contains("`r`n")) { "`r`n" } else { "`n" }
$ws.Encoding = $Utf8
$ws.OmitXmlDeclaration = $doc.FirstChild.NodeType -ne [Xml.XmlNodeType]::XmlDeclaration
$ms = [IO.MemoryStream]::new()
$xw = [Xml.XmlWriter]::Create($ms, $ws)
$doc.Save($xw)
$xw.Dispose()
$aclText = $Utf8.GetString($ms.ToArray()) + $ws.NewLineChars
if ($aclText -ne $aclOld) { [IO.File]::WriteAllText($acl, $aclText, $Utf8) }

# (g) start
if (-not $NoStart) {
    Start-Process -FilePath (Join-Path $MtaServer "MTA Server.exe") -WorkingDirectory $MtaServer
    Write-Host "Server starting. Connect to 127.0.0.1:22003. Log: $Dm\logs\scripts.log"
}
