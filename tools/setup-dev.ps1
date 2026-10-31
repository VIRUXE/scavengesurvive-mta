# Installs the dev toolchain: Python deps, hererocks Lua 5.1 + luacheck, stylua.
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
python -m pip install --upgrade pip hererocks | Out-Null
python -m pip install -e . | Out-Null
# hererocks runs LuaRocks' install.bat from its temp dir; that fails when cwd is excluded from exe lookup.
Remove-Item Env:NoDefaultCurrentDirectoryInExePath -ErrorAction SilentlyContinue
if (-not (Test-Path ".lua/bin/lua.exe")) { python -m hererocks .lua -l 5.1.5 -r latest }
# hererocks' MinGW config links native rocks against MSVCR80, which no modern Windows has; the WinLibs
# toolchain is UCRT-based, so link against that instead.
if ((& .lua/bin/luarocks.bat config variables.CC) -match "gcc") { & .lua/bin/luarocks.bat config variables.MSVCRT ucrt }
& .lua/bin/luarocks.bat install luacheck
& .lua/bin/luarocks.bat install dkjson
if (-not (Get-Command stylua -ErrorAction SilentlyContinue)) {
    Write-Host "Installing StyLua via winget"
    winget install --id JohnnyMorganz.StyLua -e --silent --accept-package-agreements --accept-source-agreements
}
Write-Host "OK. Run: .lua/bin/luacheck resources ; stylua --check resources"
