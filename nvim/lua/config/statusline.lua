-- =============================================================================
-- STATUSLINE
-- =============================================================================

local M = {}

-- -----------------------------------------------------------------------------
-- Получение режима
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
-- Цвета
-- -----------------------------------------------------------------------------

local function setup_statusline_colors()
    local light = vim.fn.filereadable(vim.fn.expand("~/.lightmode")) == 1

    -- Цвета блока режима
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

    -- Основные цвета
    local file_bg   = light and "#d5c4a1" or "#3c3836"
    local file_fg   = light and "#3c3836" or "#ebdbb2"

    local right_bg  = light and "#bdae93" or "#504945"
    local right_fg  = light and "#3c3836" or "#ebdbb2"

    local mode_fg   = "#ffffff"

    -- Фон всего statusline
    vim.api.nvim_set_hl(0, "StatusLine", {
        bg = file_bg,
        fg = file_fg,
    })

    -- Режимы
    vim.api.nvim_set_hl(0, "SLModeNormal", {
        bg = mode_colors.normal,
        fg = mode_fg,
        bold = true,
    })

    vim.api.nvim_set_hl(0, "SLModeInsert", {
        bg = mode_colors.insert,
        fg = mode_fg,
        bold = true,
    })

    vim.api.nvim_set_hl(0, "SLModeVisual", {
        bg = mode_colors.visual,
        fg = mode_fg,
        bold = true,
    })

    vim.api.nvim_set_hl(0, "SLModeReplace", {
        bg = mode_colors.replace,
        fg = mode_fg,
        bold = true,
    })

    vim.api.nvim_set_hl(0, "SLModeTerminal", {
        bg = mode_colors.terminal,
        fg = mode_fg,
        bold = true,
    })

    vim.api.nvim_set_hl(0, "SLModeCommand", {
        bg = mode_colors.command,
        fg = mode_fg,
        bold = true,
    })

    vim.api.nvim_set_hl(0, "SLModeOther", {
        bg = mode_colors.other,
        fg = mode_fg,
        bold = true,
    })

    -- Файл
    vim.api.nvim_set_hl(0, "SLFile", {
        bg = file_bg,
        fg = file_fg,
    })

    -- Разделитель режим → файл
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

    -- Правая часть
    vim.api.nvim_set_hl(0, "SLRight", {
        bg = right_bg,
        fg = right_fg,
    })

    -- Разделитель файл → правая часть
    vim.api.nvim_set_hl(0, "SLRightSep", {
        fg = file_bg,
        bg = right_bg,
    })

    -- Разделитель справа
    vim.api.nvim_set_hl(0, "SLRightEnd", {
        fg = right_bg,
        bg = file_bg,
    })
end

-- -----------------------------------------------------------------------------
-- Statusline
-- -----------------------------------------------------------------------------

function M.render()
    
    local mode_name, mode_hl = mode_info()

    -- Имя файла
    local file = vim.fn.expand("%:t")
    if file == "" then
        file = "[No Name]"
    end

    -- Modified
    local modified = vim.bo.modified and " [+]" or ""

    -- Статистика буферов
    local bufs = vim.fn.getbufinfo({ buflisted = 1 })

    local b_idx = 0
    for i, b in ipairs(bufs) do
        if b.bufnr == vim.fn.bufnr("%") then
            b_idx = i
            break
        end
    end

    local buffers = ""
    if #bufs > 1 then
        buffers = string.format(" B:%d/%d ", b_idx, #bufs)
    end

    -- Опции
    local list = vim.opt.list:get() and "LST:on" or "LST:off"
    local wrap = vim.opt.wrap:get() and "WRP:on" or "WRP:F7"
    local number = vim.opt.number:get() and "NUM:on" or "NUM:F8"

    local spell = "SPELL:OFF:F9"

    if vim.opt.spell:get() then
        local lang = vim.opt.spelllang:get()[1]

        if lang == "uk" then
            spell = "SPELL:UA:F9"
        elseif lang == "en_us" then
            spell = "SPELL:EN:F9"
        else
            spell = "SPELL:" .. lang:upper() .. ":F9"
        end
    end

    local position = string.format(
        " %d/%d:%d ",
        vim.fn.line("."),
        vim.fn.line("$"),
        vim.fn.col(".")
    )

    -- ВАЖНО:
    --  имеет цвет предыдущего блока и фон следующего.
    --
    -- Поэтому получается:
    --
    -- [ NORMAL ][ filename ][ options ]
    --

    return table.concat({
        "%#" .. mode_hl .. "# ",
        mode_name,
        " ",

        "%#SLModeSep#",

        "%#SLFile# ",
        file,
        modified,
        buffers,
        " ",

        "%=",

        "%#SLRightEnd#",

        "%#SLRight# ",
        list,
        "  ",
        wrap,
        "  ",
        number,
        "  ",
        spell,
        position,

        " ",
    })
end

-- -----------------------------------------------------------------------------
-- Устанавливаем statusline
-- -----------------------------------------------------------------------------

vim.opt.statusline = "%!v:lua.require'config.statusline'.render()"

-- -----------------------------------------------------------------------------
-- Обновление цветов
-- -----------------------------------------------------------------------------

local group = vim.api.nvim_create_augroup(
    "StatusLineColors",
    { clear = true }
)

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

-- Первичная установка
setup_statusline_colors()

return M
