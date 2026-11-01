-- Read-only information windows in CEGUI (/mstats, /rules, /admins, /credits, /help, /chatinfo), sized to their
-- content. A spec from the server (exports.ui:showInfo) holds:
--   title                window caption
--   header, footer       optional SA-MP text (colour codes) shown as coloured, word-wrapped paragraphs
--   columns + rows       a table: rows are arrays of cells, optional colour = "#RRGGBB" per row
--   text                 the body as coloured paragraphs in a scroll pane (when there is no table)
-- Close, Escape or Enter shuts it; one window at a time.
return function(ctx)
    local info = ctx.info
    local FONT, PAD, GAP, BUTTON_H, ROW_H = "default-normal", 12, 8, 28, 16
    local MIN_W, MAX_W, MAX_TABLE_ROWS, MAX_TEXT_H = 360, 720, 18, 360
    local win = nil
    local M = {}

    -- widths in CEGUI's own font: a hidden label measures (dx fonts run narrower and clipped the columns)
    local ruler = guiCreateLabel(0, 0, 10, 10, "", false)
    guiSetVisible(ruler, false)
    guiSetFont(ruler, FONT)

    local function textWidth(text)
        guiSetText(ruler, text)
        return guiLabelGetTextExtent(ruler)
    end

    function M.close()
        if not win then
            return
        end
        if isElement(win.window) then
            destroyElement(win.window)
        end
        removeEventHandler("onClientKey", root, win.onKey)
        showCursor(false)
        guiSetInputMode(win.inputMode)
        win = nil
    end

    -- the width a paragraph block needs unwrapped, capped by the caller
    local function paragraphsWidth(paras)
        local w = 0
        for _, p in ipairs(paras) do
            w = math.max(w, textWidth(p.text) + p.indent * 16)
        end
        return w
    end

    -- coloured paragraphs as word-wrapped labels from y down inside parent; returns the y below the last one
    local function placeParagraphs(parent, paras, x, y, width)
        local lineH = 15
        for _, p in ipairs(paras) do
            if p.gap then
                y = y + GAP
            end
            local indent = p.indent * 16
            local lines = math.max(1, math.ceil(textWidth(p.text) / math.max(1, width - indent - 4)))
            local label = guiCreateLabel(x + indent, y, width - indent, lines * lineH + 2, p.text, false, parent)
            guiLabelSetHorizontalAlign(label, "left", true)
            guiSetFont(label, FONT)
            local r, g, b = p.colour[1], p.colour[2], p.colour[3]
            guiLabelSetColor(label, r, g, b)
            y = y + lines * lineH + 2
        end
        return y
    end

    local function columnWidths(spec)
        local widths = {}
        for i, name in ipairs(spec.columns) do
            widths[i] = textWidth(name) + 24
        end
        for _, row in ipairs(spec.rows or {}) do
            for i = 1, #spec.columns do
                widths[i] = math.max(widths[i], textWidth(tostring(row[i] or "")) + 24)
            end
        end
        return widths
    end

    local function buildTable(parent, spec, x, y, width, widths)
        local rows = spec.rows or {}
        local visible = math.min(math.max(#rows, 3), MAX_TABLE_ROWS)
        local height = (visible + 1) * ROW_H + 14
        local grid = guiCreateGridList(x, y, width, height, false, parent)
        guiGridListSetSortingEnabled(grid, false)
        local total = 0
        for _, w in ipairs(widths) do
            total = total + w
        end
        local scale = (width - 32) / total -- room for the vertical scrollbar, so no horizontal one appears
        for i, name in ipairs(spec.columns) do
            guiGridListAddColumn(grid, name, widths[i] * scale / width)
        end
        for _, row in ipairs(rows) do
            local r = guiGridListAddRow(grid)
            local colour = info.hex(row.colour) or info.WHITE
            for i = 1, #spec.columns do
                guiGridListSetItemText(grid, r, i, tostring(row[i] or ""), false, false)
                guiGridListSetItemColor(grid, r, i, colour[1], colour[2], colour[3])
            end
        end
        return y + height
    end

    function M.show(spec)
        M.close()
        if type(spec) ~= "table" then
            return
        end
        local header = info.paragraphs(spec.header)
        local footer = info.paragraphs(spec.footer)
        local body = spec.columns and {} or info.paragraphs(spec.text)
        local widths = spec.columns and columnWidths(spec)
        local want = math.max(textWidth(info.plain(spec.title)) + 60, paragraphsWidth(body) + 30)
        if widths then
            local sum = 0
            for _, w in ipairs(widths) do
                sum = sum + w
            end
            want = math.max(want, sum + 24)
        end
        local sw, sh = guiGetScreenSize()
        local w = math.floor(math.min(math.max(want + PAD * 2, MIN_W), MAX_W, sw - 40))
        local inner = w - PAD * 2

        -- lay out at an arbitrary height first, then size the window to what was placed
        local window = guiCreateWindow(0, 0, w, sh, info.plain(spec.title), false)
        guiWindowSetSizable(window, false)
        local y = 28
        if #header > 0 then
            y = placeParagraphs(window, header, PAD, y, inner) + GAP
        end
        if widths then
            y = buildTable(window, spec, PAD, y, inner, widths) + GAP
        elseif #body > 0 then
            local pane = guiCreateScrollPane(PAD, y, inner, MAX_TEXT_H, false, window)
            local bottom = placeParagraphs(pane, body, 0, 0, inner - 20)
            local paneH = math.min(bottom + 4, MAX_TEXT_H)
            guiSetSize(pane, inner, paneH, false)
            y = y + paneH + GAP
        end
        if #footer > 0 then
            y = placeParagraphs(window, footer, PAD, y, inner) + GAP
        end
        local button = guiCreateButton((w - 110) / 2, y, 110, BUTTON_H, "Close", false, window)
        local h = y + BUTTON_H + PAD
        guiSetSize(window, w, h, false)
        guiSetPosition(window, (sw - w) / 2, (sh - h) / 2, false)

        local function onKey(key, press)
            if press and (key == "escape" or key == "enter" or key == "num_enter") then
                cancelEvent()
                M.close()
            end
        end
        win = { window = window, inputMode = guiGetInputMode(), onKey = onKey }
        addEventHandler("onClientKey", root, onKey)
        addEventHandler("onClientGUIClick", button, M.close, false)
        showCursor(true)
        guiSetInputMode("no_binds")
    end

    return M
end
