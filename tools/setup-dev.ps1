# Installs the dev toolchain: Python deps, hererocks Lua 5.1 + busted/luacheck/luacov, stylua.
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
python -m pip install --upgrade pip hererocks | Out-Null
python -m pip install -e ".[dev]" | Out-Null
# hererocks runs LuaRocks' install.bat from its temp dir; that fails when cwd is excluded from exe lookup.
Remove-Item Env:NoDefaultCurrentDirectoryInExePath -ErrorAction SilentlyContinue
if (-not (Test-Path ".lua/bin/lua.exe")) { python -m hererocks .lua -l 5.1.5 -r latest }
& .lua/bin/luarocks.bat install busted
& .lua/bin/luarocks.bat install luacheck
& .lua/bin/luarocks.bat install luacov
& .lua/bin/luarocks.bat install dkjson
if (-not (Get-Command stylua -ErrorAction SilentlyContinue)) {
    Write-Host "Installing StyLua via winget"
    winget install --id JohnnyMorganz.StyLua -e --silent --accept-package-agreements --accept-source-agreements
}
Write-Host "OK. Run: .lua/bin/busted tests/lua ; .lua/bin/luacheck resources ; stylua --check resources ; pytest -q"
