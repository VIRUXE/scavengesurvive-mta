# Patched MTA server (server-side buildings)

**When:** installing or updating the MTA server, on the dev box or production. The `maps` resource builds the static
maps on the server with `createBuilding` (`maps/server/build.lua`), and the published MTA 1.6.0 server builds
(branch `release/1.6.0`) get server-side buildings wrong. Every server that runs `maps` needs the patched
`deathmatch` module below; core, the launcher and the other modules stay the official ones.

**Why:** the fixes are on `master` only, not on `release/1.6.0` (checked at 24160, `a5cc07d71`, 2026-11-07):

| Bug on the published 1.6.0 server | Effect | Upstream fix |
| --- | --- | --- |
| `CMapManager::SendMapInformation` never adds buildings to the join packet | a player who joins after the map was built sees none of its 9,850 buildings | [#4837](https://github.com/multitheftauto/mtasa-blue/pull/4837) (`59fa331`) |
| `CEntityAddPacket::Write` writes a building's interior a second time, which the client does not read | every element after the first building in a packet is misread: buildings created live crash or desync clients | #4837 |
| `createBuilding` does not put the building in its resource's element group | buildings outlive their resource (handed to root on stop), so `rr maps` doubled the map | #4837 |
| `getElementModel` / `getElementRotation` have no building case | both return false for buildings on the server | [#5350](https://github.com/multitheftauto/mtasa-blue/pull/5350) (`8d43487`) |

`server-config/mta-patches/server-buildings.patch` is the server-side hunks of those two PRs (their client hunks are not
needed: official 1.6 clients join the patched server and see every building). Worth asking upstream for a
backport of #4837's server hunks and #5350 to `release/1.6.0`; once a published build carries them, this runbook
and the patch go.

The module's version string stays the official one (`1.6.0-9.<build>.0`), so `getVersion()` and the server browser
show nothing different and clients need nothing. That is also why `min_mta_version` in `maps/meta.xml` cannot ask
for it.

## Base commit and build number

Build from the `release/1.6.0` commit of the target server's build, with `server-config/mta-patches/build_overrides.h`
copied over `Shared/build_overrides.h` and `MTASA_VERSION_BUILD` set to that build: core compares the module's
`GetLibMtaVersion` string with its own and refuses a module whose build differs.

- The build: `rcon.ps1 lua "return getVersion().sortable"` (`-Prod` for production), or `strings deathmatch.so |
  grep 'MTA:SA Server v'`.
- The commit: `release/1.6.0` is one "Force rebuild" commit per nightly; match the build's date
  (`https://nightly.mtasa.com/` lists recent builds with dates, older ones by the server files' mtime) to the commit.
  From `b712cbb45` (2026-09-16) to `a5cc07d71` (24160) the only source change is `SharedUtil::IsGTAProcess`
  (client-only), so any build in that range compiles from the same server source.
  Known: 24153 = `b06a2afbd` (2026-10-06, production), 24160 = `a5cc07d71` (2026-11-07, dev box).

## Build on Windows (dev box, 32-bit `deathmatch.dll`)

Needs Visual Studio with the C++ workload (VS 18 / toolset v145 used).

```powershell
git clone --branch release/1.6.0 https://github.com/multitheftauto/mtasa-blue.git mta-1.6; cd mta-1.6
git checkout <commit>
git apply <repo>\server-config\mta-patches\server-buildings.patch
copy <repo>\server-config\mta-patches\build_overrides.h Shared\build_overrides.h   # then set the build number
utils\premake5.exe vs2026
msbuild Build\Deathmatch.vcxproj /p:Configuration=Nightly /p:Platform=Win32 /p:PlatformToolset=v145 /m
```

The result is `Bin\server\mods\deathmatch\deathmatch.dll`. Keep the clone out of `%TEMP%` (MSBuild warns about
incremental builds there).

## Build on Linux x64 (production, `deathmatch.so`)

Upstream builds `release/1.6.0` in `utils/docker/Dockerfile` (Ubuntu focal, GCC 10). Without docker, build natively
on the host that will run it (so its glibc is new enough). `release/1.6.0` does not compile with GCC 14+ (the vendored
Lua's `lapi.c`, and the Lua argument parser rejects `noexcept` functions); `server-config/mta-patches/linux-gcc15.patch`
is upstream's own fix from `master` (`f5e59ac65` and `362e171e4`, "Fix compilation issues after update to GCC 15"),
rebased onto `release/1.6.0` and limited to what `deathmatch` compiles: it only drops `noexcept` from Lua definitions
and fixes types, nothing a script can see. Production's (nasa, Debian testing) was built with `gcc-15`:

```sh
git clone --branch release/1.6.0 https://github.com/multitheftauto/mtasa-blue.git src && cd src
git checkout <commit>
git apply <repo>/server-config/mta-patches/server-buildings.patch
git apply <repo>/server-config/mta-patches/linux-gcc15.patch      # GCC 14 or newer only
cp <repo>/server-config/mta-patches/build_overrides.h Shared/build_overrides.h   # then set the build number
utils/premake5 --gccprefix=x86_64-linux-gnu- --os=linux gmake
make -C Build -j"$(nproc)" config=release_x64 AR=gcc-ar-15 CC=gcc-15 CXX=g++-15 Deathmatch
```

Add `LDFLAGS="-static-libstdc++ -static-libgcc"` to that `make` (upstream's `GLIBC_COMPAT` build links them
statically too), then `strip --strip-debug` the result, `Bin/server/x64/deathmatch.so` (250 MB with debug info, 15 MB
without). Before installing, compare it with the official one:
`strings <so> | grep 'MTA:SA Server v'` must print the same line, `nm -D --defined-only` the same exported symbols
of MTA's own (`InitServer`, `ReleaseServer`, `GetLibMtaVersion`, the `lua_*`; the libstdc++ internals it re-exports
differ with the compiler), the same `NEEDED` libraries (`libm`, `libc`, `ld-linux`), and `ldd` must find them all.
A module built natively needs the build host's glibc or newer.

To see it load without touching the live server, copy `mta-server64` and `x64/*.so*` into a scratch directory, put
the new module in its `x64/`, give it a stock `mtaserver.conf` on other ports (`serverport`, `httpport`, `ase 0`,
`donotbroadcastlan 1`) and a test resource that calls `createBuilding`, the getters and a stop and start, and run
`timeout 90 ./mta-server64 -n -u -t`: core refuses a module of another build at start.

## Swap and roll back

The server loads the module only at start, so a swap takes a full server restart.

- **Windows:** stop the server, rename `$DM\deathmatch.dll` to `deathmatch.dll.<build>.bak`, copy the patched one in,
  start it. Roll back: put the `.bak` back.
- **Linux:** `$MTA/x64/deathmatch.so`. Never copy over a loaded `.so`: `install -m 755 <new> $MTA/x64/deathmatch.so.new`,
  `cp -p deathmatch.so deathmatch.so.<build>.bak`, `mv deathmatch.so.new deathmatch.so`, then restart
  (`start-stop-restart.md`). Roll back: `mv deathmatch.so.<build>.bak deathmatch.so` and restart again.

An MTA server update replaces the module with the official one again: rebuild for the new build number first.

## Check

- The server log shows no `deathmatch` load error and `getVersion().sortable` is unchanged.
- `rcon.ps1 lua "return #getElementsByType('building'), exports.maps:getMapStats().buildings"`: both 9850, and still
  9850 after `rr maps` (19,700 means buildings outlived the resource: the official module is loaded).
- The getters: `rcon.ps1 lua "local b = getElementsByType('building')[1] return getElementModel(b), getElementRotation(b)"`
  returns numbers, not false.
- A client that joins after the start sees the map's buildings (on the dev box: `clua <player> return
  #getElementsByType('building')` gives 9850).
- With sageom: `rcon.ps1 lua "return exports.sageom:getStats().buildingsKnown"` is 9850 (`server-collision.md`).
