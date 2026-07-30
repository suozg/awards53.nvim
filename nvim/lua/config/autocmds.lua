-- =============================================================================
-- AUTOCMDS
-- =============================================================================
local group = vim.api.nvim_create_augroup("UserConfig", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "org", "text" },
    callback = function()
        vim.opt_local.spell = true
        vim.opt_local.spelllang = { "uk", "en_us" }
        
        -- Увімкнути класичний синтаксис і змусити його перевіряти весь текст
        vim.cmd("syntax on")
        vim.cmd("syntax spell toplevel")
    end,
})

vim.api.nvim_create_autocmd("TextYankPost", {
    group = group,
    callback = function()
        vim.highlight.on_yank({ timeout = 200 })
    end,
})

vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.org",
    callback = function()
        vim.fn.jobstart({ "pkill", "-RTMIN+10", "dwmblocks" })
    end,
})

vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function()
        vim.api.nvim_set_hl(0, "StatusLine", { link = "StatusLineInsert" })
    end,
})

vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function()
        vim.api.nvim_set_hl(0, "StatusLine", { link = "StatusLineNormal" })
    end,
})


-- -----------------------------------------------------------------------------
-- Управління розкладкою клавіатури (xkb-switch + dwmblocks)
-- -----------------------------------------------------------------------------
local saved_layout = "us"

local function save_current_layout()
    local handle = io.popen("xkb-switch -p")
    if handle then
        local current = handle:read("*l")
        handle:close()
        if current and current ~= "" then
            saved_layout = current
        end
    end
end

local function force_switch_to_us()
    vim.fn.system("xkb-switch -s us")
    vim.fn.jobstart({ "pkill", "-RTMIN+1", "dwmblocks" })
end

-- Повертаємо розкладку, яка була до виходу з Insert
vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function()
        if saved_layout ~= "" then
            vim.fn.jobstart({ "xkb-switch", "-s", saved_layout })
            vim.fn.jobstart({ "pkill", "-RTMIN+1", "dwmblocks" })
        end
    end,
})

-- При виході з Insert зберігаємо мову та перемикаємо на 'us'
vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function()
        save_current_layout()
        force_switch_to_us()
    end,
})

-- При переході в режим команд (:, /, ?) ПРИМУСОВО скидаємо на 'us' (без збереження, щоб не перезаписати saved_layout)
vim.api.nvim_create_autocmd("CmdlineEnter", {
    group = group,
    callback = function()
        force_switch_to_us()
    end,
})


-- -----------------------------------------------------------------------------
-- Кольори орфографії для будь-яких тем та терміналів
-- -----------------------------------------------------------------------------
vim.api.nvim_create_autocmd({ "ColorScheme", "VimEnter" }, {
    group = group,
    pattern = "*",
    callback = function()
        vim.api.nvim_set_hl(0, "SpellBad", { 
            fg = "Red",     
            ctermbg = "Red",    
            ctermfg = "White", 
            bold = true 
        })
    end,
})

vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "orgagenda" }, 
    callback = function()
        vim.opt_local.colorcolumn = ""
    end,
})
