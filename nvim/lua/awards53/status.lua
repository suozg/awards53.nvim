local M = {}

local state = require("awards53.state")

-- Чтобы не перерисовывать statusline, если цвет разделителя не изменился
local last_mode_sep_colors = nil

-- -----------------------------------------------------------------------------
-- Режими
-- -----------------------------------------------------------------------------
local function mode_info()
    local mode = vim.fn.mode()

    local modes = {
        ['n']      = { 'NORMAL', 'SLModeNormal' },
        ['no']     = { 'N-OPERATOR', 'SLModeNormal' },
        ['v']      = { 'VISUAL', 'SLModeVisual' },
        ['V']      = { 'V-LINE', 'SLModeVisual' },
        ['\22']    = { 'V-BLOCK', 'SLModeVisual' },
        ['s']      = { 'SELECT', 'SLModeVisual' },
        ['S']      = { 'S-LINE', 'SLModeVisual' },
        ['\19']    = { 'S-BLOCK', 'SLModeVisual' },
        ['i']      = { 'INSERT', 'SLModeInsert' },
        ['ic']     = { 'INSERT', 'SLModeInsert' },
        ['ix']     = { 'INSERT', 'SLModeInsert' },
        ['R']      = { 'REPLACE', 'SLModeReplace' },
        ['Rc']     = { 'REPLACE', 'SLModeReplace' },
        ['Rx']     = { 'REPLACE', 'SLModeReplace' },
        ['Rv']     = { 'V-REPLACE', 'SLModeReplace' },
        ['c']      = { 'COMMAND', 'SLModeCommand' },
        ['cv']     = { 'VIM EX', 'SLModeCommand' },
        ['ce']     = { 'EX', 'SLModeCommand' },
        ['r']      = { 'PROMPT', 'SLModeOther' },
        ['rm']     = { 'MORE', 'SLModeOther' },
        ['r?']     = { 'CONFIRM', 'SLModeOther' },
        ['!']      = { 'SHELL', 'SLModeTerminal' },
        ['t']      = { 'TERMINAL', 'SLModeTerminal' },
    }

    local current = modes[mode]
    if current then
        return current[1], current[2]
    else
        return mode:upper(), 'SLModeOther'
    end
end

-- -----------------------------------------------------------------------------
-- Кольори
-- -----------------------------------------------------------------------------
local function setup_statusline_colors()
    local light = vim.fn.filereadable(vim.fn.expand("~/.lightmode")) == 1

    local file_bg = light and "#d5c4a1" or "#3c3836"
    local file_fg = light and "#3c3836" or "#ebdbb2"

    local info_bg = light and "#ebdbb2" or "#4f4842"
    local info_fg = light and "#3c3836" or "#ebdbb2"

    local right_bg = light and "#bdae93" or "#504945"
    local right_fg = light and "#3c3836" or "#ebdbb2"

    local mode_bgs = {
        SLModeNormal   = light and "#458588" or "#83a598",
        SLModeInsert   = light and "#b8bb26" or "#b8bb26",
        SLModeVisual   = light and "#d3869b" or "#d3869b",
        SLModeReplace  = light and "#fb4934" or "#fb4934",
        SLModeCommand  = light and "#fe8019" or "#fe8019",
        SLModeTerminal = light and "#8ec07c" or "#8ec07c",
        SLModeOther    = light and "#d5c4a1" or "#504945",
    }

    for hl, bg in pairs(mode_bgs) do
        vim.api.nvim_set_hl(0, hl, { bg = bg, fg = "#282828", bold = true })
    end

    vim.api.nvim_set_hl(0, "StatusLine", { bg = file_bg, fg = file_fg })
    vim.api.nvim_set_hl(0, "SLFile", { bg = file_bg, fg = file_fg })

    local _, mode_hl = mode_info()
    local current_mode_bg = mode_bgs[mode_hl] or file_bg
    vim.api.nvim_set_hl(0, "SLModeSep", { fg = current_mode_bg, bg = file_bg })

    vim.api.nvim_set_hl(0, "SLFileSep", { fg = file_bg, bg = info_bg })
    vim.api.nvim_set_hl(0, "SLInfo", { bg = info_bg, fg = info_fg })
    vim.api.nvim_set_hl(0, "SLInfoSep", { fg = right_bg, bg = info_bg })
    vim.api.nvim_set_hl(0, "SLRight", { bg = right_bg, fg = right_fg })

    -- сбрасываем кэш, потому что тема изменилась
    last_mode_sep_colors = nil
end

-- -----------------------------------------------------------------------------
-- Рендеринг
-- -----------------------------------------------------------------------------
function M.render()
    local mode_name, mode_hl = mode_info()

    -- Нельзя переопределять hl на каждый render, если цвета не поменялись.
    local mode_hl_info = vim.api.nvim_get_hl(0, { name = mode_hl, link = false })
    local file_hl_info = vim.api.nvim_get_hl(0, { name = "SLFile", link = false })

    if mode_hl_info and mode_hl_info.bg and file_hl_info and file_hl_info.bg then
        local new_mode_bg = string.format("#%06x", mode_hl_info.bg)
        local new_file_bg = string.format("#%06x", file_hl_info.bg)
        local new_colors = new_mode_bg .. "|" .. new_file_bg

        if last_mode_sep_colors ~= new_colors then
            vim.api.nvim_set_hl(0, "SLModeSep", {
                fg = new_mode_bg,
                bg = new_file_bg,
            })
            last_mode_sep_colors = new_colors
        end
    end

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
        "h◄ l► [[◀◀ ]]▶▶ #g m/[m]🔖 │ " ..
        "S O⇄ A dp✥ dd✗ y⎘ p󰆑 :w🖪 | u c-r U󰓦 | ? | :q⏻"

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

vim.api.nvim_create_autocmd({ "ColorScheme", "VimEnter" }, {
    group = group,
    callback = function()
        setup_statusline_colors()
    end,
})

setup_statusline_colors()

return M
