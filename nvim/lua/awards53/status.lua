local M = {}

local state = require("awards53.state")

-- -----------------------------------------------------------------------------
-- Кольори
-- -----------------------------------------------------------------------------

local function setup_statusline_colors()
    local light = vim.fn.filereadable(vim.fn.expand("~/.lightmode")) == 1

    local file_bg   = light and "#d5c4a1" or "#3c3836"
    local file_fg   = light and "#3c3836" or "#ebdbb2"

    local info_bg   = light and "#ebdbb2" or "#4f4842"
    local info_fg   = light and "#3c3836" or "#ebdbb2"

    local right_bg  = light and "#bdae93" or "#504945"
    local right_fg  = light and "#3c3836" or "#ebdbb2"

    -- Основний фон
    vim.api.nvim_set_hl(0, "StatusLine", {
        bg = file_bg,
        fg = file_fg,
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
        "S O⇄ A dp✥ dd✗ y⎘ p󰆑 :w🖪 | u c-r U󰓦 | ? | :q⏻"

    return table.concat({
        "%#SLFile# ",
        file_name,
        " ",

        "%#SLFileSep#",

        "%#SLInfo# ",
        card_info,
        " ",
        
        "%=",

        "%#SLInfoSep#",

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
    "BufEnter",
    "WinEnter",
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
