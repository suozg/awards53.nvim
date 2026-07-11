-- =============================================================================
-- 8. STATUSLINE
-- =============================================================================
function _G.statusline()
    local function flag(opt_name, label, key)
        local enabled = vim.opt[opt_name]:get()
        return string.format("[%s:%s]", label, enabled and key or "off")
    end

    local spell_state = "OFF"
    if vim.opt.spell:get() then
        local lang = vim.opt.spelllang:get()[1]
        spell_state = (lang == "uk" and "UA" or (lang == "en_us" and "EN" or lang:upper()))
    end

    local bufs = vim.fn.getbufinfo({buflisted = 1})
    local b_idx = 0
    for i, b in ipairs(bufs) do if b.bufnr == vim.fn.bufnr('%') then b_idx = i break end end
    local b_stat = (#bufs > 1) and string.format(" [B:%d/%d] ", b_idx, #bufs) or ""

    return table.concat({
        " %f %m %y ", b_stat, "%=",
        flag("list", "LST", "F6"), " ",
        flag("wrap", "WRP", "F7"), " ",
        flag("number", "NUM", "F8"), " ",
        string.format("[SPELL:%s:F9]", spell_state),
        " %l/%L:%c "
    })
end

vim.opt.statusline = "%!v:lua.statusline()"

-- смена цвета статусбар при изменении режима
local function set_statusline_mode_colors()
    vim.api.nvim_set_hl(0, "StatusLineNormal", { bg = "#3c3836", fg = "#ebdbb2" })
    vim.api.nvim_set_hl(0, "StatusLineInsert", { bg = "#2e7d32", fg = "#ffffff" }) -- зелёный
end

set_statusline_mode_colors()





