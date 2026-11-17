-- The port's world in the server's collision (ml_sageom, https://github.com/VIRUXE/sa-geom): the module carries the
-- vanilla map, and this hands it geom/overlay.toml (tools/geom_overlay.py: the maps resource's objects and removals,
-- the puzzles' objects and the model packs' collision) once its world has loaded, so server-side ground and ray
-- queries (lib geom.lua) match what players stand on. The module reads the files itself, straight from disk.
-- An overlay stays in the module for as long as the server runs, across resource restarts, and cannot be taken out:
-- root element data "geom.overlay" holds the hash of the one applied, and a restart of this resource with the same
-- files does nothing. Changed files are not stacked over the old ones (the old removals and objects would stay):
-- geom.overlayStale is logged, root element data "geom.stale" is set (lib geom.lua then reports the world not ready,
-- so callers fall back instead of trusting a map that no longer matches) and the server has to restart for them.
-- ctx = { log }
return function(ctx)
    local log = ctx.log
    local FILES = { "geom/overlay.toml", "geom/port.map" }
    local READY_POLL_MS, READY_TRIES = 500, 240

    if type(sageomAddOverlay) ~= "function" then
        log.event("geom.unavailable", { reason = "ml_sageom not loaded" }, "warn")
        return
    end

    local parts = {}
    for _, path in ipairs(FILES) do
        local f = fileExists(path) and fileOpen(path, true)
        if not f then
            log.event("geom.overlayFailed", { reason = path .. " missing" }, "error")
            return
        end
        parts[#parts + 1] = fileRead(f, fileGetSize(f))
        fileClose(f)
    end
    local digest = hash("md5", table.concat(parts))
    local applied = getElementData(root, "geom.overlay")
    if applied == digest then
        setElementData(root, "geom.stale", false, false)
        return
    elseif applied then
        setElementData(root, "geom.stale", true, false)
        log.event("geom.overlayStale", { applied = applied, current = digest }, "warn")
        return
    end

    -- sageomAddOverlay takes a path relative to the server root
    local res = getThisResource()
    local path = "mods/deathmatch/resources/"
        .. getResourceOrganizationalPath(res)
        .. "/"
        .. getResourceName(res)
        .. "/"
        .. FILES[1]
    local tries = 0
    local function apply()
        if not sageomIsReady() then
            tries = tries + 1
            if tries >= READY_TRIES then
                log.event("geom.overlayFailed", { reason = "world never loaded" }, "error")
            else
                setTimer(apply, READY_POLL_MS, 1)
            end
            return
        end
        local started = getTickCount()
        local ok, summary = sageomAddOverlay(path)
        if not ok then
            log.event("geom.overlayFailed", { reason = tostring(summary) }, "error")
            return
        end
        setElementData(root, "geom.overlay", digest, false)
        log.event("geom.overlayApplied", { ms = getTickCount() - started, summary = summary })
    end
    apply()
end
