-- The SA-MP textdraw canvas: 640x480 units, scaled uniformly by screenH/480 and anchored per element, so the
-- upstream numbers (docs/ui-reference-samp.md) are used as they are and widescreen does not stretch them.
local canvas = {}

-- SA-MP textdraw font id -> MTA built-in font. Font 1 (GTA's subtitle font) has no built-in twin.
local FONTS = { [0] = "diploma", [1] = "default-bold", [2] = "bankgothic", [3] = "pricedown" }
-- Line pitch in canvas units per 1.0 of letter-size Y (measured on the 720p footage: 0.3/1.5 -> 22 px).
local LINE_UNITS = 9.8
-- dxDrawText line height in pixels at scale 1 for each font.
local DX_LINE_PX = { ["default-bold"] = 15, bankgothic = 16, diploma = 17, pricedown = 17 }
-- Horizontal correction per font at the textdraw's native 1:4 letter aspect, measured against the footage:
-- MTA's Bank Gothic is much wider than GTA's condensed font 2, Tahoma Bold narrower than GTA's font 1.
local X_FACTOR = { ["default-bold"] = 1.5, bankgothic = 0.72, diploma = 1, pricedown = 1 }
local NATIVE_ASPECT = 0.25 -- letter-size X / Y at which the glyphs keep their native shape (0.5 / 2.0)
-- Vertical correction: Bank Gothic glyphs are taller for their line pitch than GTA's font 2.
local Y_FACTOR = { bankgothic = 0.85 }

function canvas.new(screenW, screenH)
    return { sw = screenW, sh = screenH, s = screenH / 480 }
end

-- Canvas x -> pixel x. anchor: "left" (default), "right" (x measured from the right edge of the 640 canvas)
-- or "center" (x measured from the canvas middle), so elements stay on their screen edge on any aspect ratio.
function canvas.x(c, units, anchor)
    if anchor == "right" then
        return c.sw - (640 - units) * c.s
    elseif anchor == "center" then
        return c.sw / 2 + (units - 320) * c.s
    end
    return units * c.s
end

function canvas.y(c, units)
    return units * c.s
end

function canvas.len(c, units)
    return units * c.s
end

function canvas.font(id)
    return FONTS[id] or FONTS[1]
end

function canvas.lineHeight(c, letterY)
    return letterY * LINE_UNITS * c.s
end

-- dxDrawText scale that gives a textdraw of letter-size Y its line pitch.
function canvas.textScale(c, letterY, fontId)
    local font = canvas.font(fontId)
    return canvas.lineHeight(c, letterY) / (DX_LINE_PX[font] or 15) * (Y_FACTOR[font] or 1)
end

-- Horizontal scale relative to the vertical one for a textdraw letter size (X, Y) in the given font.
function canvas.xScale(fontId, lx, ly)
    local factor = X_FACTOR[canvas.font(fontId)] or 1
    return factor * ((lx or 0.3) / (ly or 1.5)) / NATIVE_ASPECT
end

-- SA-MP 0xRRGGBBAA -> r, g, b, a
function canvas.rgba(v)
    v = v % 0x100000000
    local r = math.floor(v / 0x1000000) % 256
    local g = math.floor(v / 0x10000) % 256
    local b = math.floor(v / 0x100) % 256
    return r, g, b, v % 256
end

-- progress2 bar geometry (Southclaws/progress2): background box, a half-alpha fill and the value box inset by
-- 1.2 x 1.0 units. All in canvas units; frac in [0, 1].
function canvas.progressBar(x, y, w, h, frac)
    frac = math.max(0, math.min(1, frac or 0))
    local ix, iy = x + 1.2, y + 1.0
    local iw, ih = w - 2.4, h - 2.0
    return {
        back = { x = x, y = y, w = w, h = h },
        fill = { x = ix, y = iy, w = iw, h = ih },
        value = { x = ix, y = iy, w = iw * frac, h = ih },
    }
end

return canvas
