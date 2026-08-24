local M = {}

local state = require("awards53.state")

-- -----------------------------------------------------------------------------
-- Отримання режиму
-- -----------------------------------------------------------------------------

local function mode_info()
    local mode = vim.fn.mode()

    if mode:match("^[nN]") then
        return "NORMAL", "SLModeNormal"
    elseif mode == "i" or mode == "ic" or mode == "ix" then
        return "INSERT", "SLModeInsert"
    elseif mode:match("^[vV\22]") then
        return "VISUAL", "SLModeVisual"
    elseif mode == "R" or mode == "Rc" then
        return "REPLACE", "SLModeReplace"
    elseif mode == "t" then
        return "TERMINAL", "SLModeTerminal"
    elseif mode == "c" then
        return "COMMAND", "SLModeCommand"
    else
        return mode:upper(), "SLModeOther"
    end
end

-- -----------------------------------------------------------------------------
-- Кольори
-- -----------------------------------------------------------------------------

local function setup_statusline_colors()
    local light = vim.fn.filereadable(vim.fn.expand("~/.lightmode")) == 1

    local mode_colors
    if light then
        mode_colors = {
            normal   = "#458588",
            insert   = "#689d6a",
            visual   = "#b16286",
            replace  = "#cc241d",
            terminal = "#d65d0e",
            command  = "#98971a",
            other    = "#665c54",
        }
    else
        mode_colors = {
            normal   = "#005577",
            insert   = "#2e7d32",
            visual   = "#8f3f71",
            replace  = "#cc241d",
            terminal = "#d65d0e",
            command  = "#98971a",
            other    = "#3c3836",
        }
    end

    local file_bg   = light and "#d5c4a1" or "#3c3836"
    local file_fg   = light and "#3c3836" or "#ebdbb2"

    local info_bg   = light and "#ebdbb2" or "#4f4842"
    local info_fg   = light and "#3c3836" or "#ebdbb2"

    local right_bg  = light and "#bdae93" or "#504945"
    local right_fg  = light and "#3c3836" or "#ebdbb2"

    local mode_fg   = "#ffffff"

    -- Основний фон
    vim.api.nvim_set_hl(0, "StatusLine", {
        bg = file_bg,
        fg = file_fg,
    })

    -- Режими
    vim.api.nvim_set_hl(0, "SLModeNormal", { bg = mode_colors.normal, fg = mode_fg, bold = true })
    vim.api.nvim_set_hl(0, "SLModeInsert", { bg = mode_colors.insert, fg = mode_fg, bold = true })
    vim.api.nvim_set_hl(0, "SLModeVisual", { bg = mode_colors.visual, fg = mode_fg, bold = true })
    vim.api.nvim_set_hl(0, "SLModeReplace", { bg = mode_colors.replace, fg = mode_fg, bold = true })
    vim.api.nvim_set_hl(0, "SLModeTerminal", { bg = mode_colors.terminal, fg = mode_fg, bold = true })
    vim.api.nvim_set_hl(0, "SLModeCommand", { bg = mode_colors.command, fg = mode_fg, bold = true })
    vim.api.nvim_set_hl(0, "SLModeOther", { bg = mode_colors.other, fg = mode_fg, bold = true })

    -- Розділювач режим → файл
    vim.api.nvim_set_hl(0, "SLModeSep", {
        fg = mode_colors[({
            SLModeNormal = "normal",
            SLModeInsert = "insert",
            SLModeVisual = "visual",
            SLModeReplace = "replace",
            SLModeTerminal = "terminal",
            SLModeCommand = "command",
            SLModeOther = "other",
        })[select(2, mode_info())] or "normal"],
        bg = file_bg,
    })

    -- Файл
    vim.api.nvim_set_hl(0, "SLFile", { bg = file_bg, fg = file_fg })

    -- Розділювач файл → інформація про картку
    vim.api.nvim_set_hl(0, "SLFileSep", { fg = file_bg, bg = info_bg })

    -- Інформація
    vim.api.nvim_set_hl(0, "SLInfo", { bg = info_bg, fg = info_fg })

    -- Розділювач інформація → права частина
    vim.api.nvim_set_hl(0, "SLInfoSep", { fg = right_bg, bg = info_bg })

    -- Права частина
    vim.api.nvim_set_hl(0, "SLRight", { bg = right_bg, fg = right_fg })

end

-- -----------------------------------------------------------------------------
-- Рендеринг
-- -----------------------------------------------------------------------------

function M.render()
    local mode_name, mode_hl = mode_info()

    local file_name = ""
    local buf = state.get_source_buffer()

    if buf and vim.api.nvim_buf_is_valid(buf) then
        local full_path = vim.api.nvim_buf_get_name(buf)
        if full_path ~= "" then
            file_name = vim.fn.fnamemodify(full_path, ":t")
        else
            file_name = "[No Name]"
        end
    end

    if file_name == "" then
        file_name = "[No Name]"
    end

    local is_modified = false
    if state.is_changed then
        is_modified = true
    end

    if buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then
        is_modified = true
    end

    local editor_ok, editor = pcall(require, "awards53.editor")
    if editor_ok and editor.buf and vim.api.nvim_buf_is_valid(editor.buf) and vim.bo[editor.buf].modified then
        is_modified = true
    end

    local mod_flag = is_modified and "%#Awards53ChangedIndicatorKarta# [+]%#SLInfo# " or " "
    local bookmark_flag = state.has_bookmark() and " 🔖" or ""

    local card_info = string.format(
        "Картка: %d/%d%s%s",
        state.index(),
        state.count(),
        mod_flag,
        bookmark_flag
    )

    local operations =
        "h◄ l► [[◀◀ ]]▶▶ #g │ " ..
        "S O⇄ A B 0 dp✥ dd✗ y⎘ p󰆑 :w🖪 :q⏻ │ ?"

    return table.concat({
        "%#" .. mode_hl .. "# ",
        mode_name,
        " ",

        "%#SLModeSep#",

        "%#SLFile# ",
        file_name,
        " ",

        "%#SLFileSep#",

        "%#SLInfo# ",
        card_info,
        " ",
        
        "%=",

        "%#SLInfoSep#",

        "%#SLRight# ",

        operations,
        " ",
    })
end

-- -----------------------------------------------------------------------------
-- Автокоманди та ініціалізація
-- -----------------------------------------------------------------------------

local group = vim.api.nvim_create_augroup("AwardsStatusLineColors", { clear = true })

vim.api.nvim_create_autocmd({
    "ModeChanged",
    "BufEnter",
    "WinEnter",
    "InsertEnter",
    "InsertLeave",
    "ColorScheme",
}, {
    group = group,
    callback = function()
        vim.schedule(function()
            setup_statusline_colors()
            vim.cmd("redrawstatus!")
        end)
    end,
})

setup_statusline_colors()

return M
