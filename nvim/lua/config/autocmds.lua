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

-- Універсальна функція для зміни розкладки, оновлення файлу та статусу в dwm
local function set_layout(layout)
    vim.fn.jobstart({ "xkb-switch", "-s", layout })
    
    -- Виправляємо тернарний оператор на звичайний if-else
    local display_text
    if layout == "ua" then
        display_text = "🌻UA"
    else
        display_text = "🗽US"
    end

    local f = io.open("/tmp/dwm_layout", "w")
    if f then
        f:write(display_text)
        f:close()
    end

    vim.fn.jobstart({ "pkill", "-RTMIN+1", "dwmblocks" })
end

-- Повертаємо розкладку, яка була до виходу з Insert
vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function()
        if saved_layout ~= "" then
            set_layout(saved_layout)
        end
    end,
})

-- При виході з Insert зберігаємо мову та перемикаємо на 'us'
vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function()
        save_current_layout()
        set_layout("us")
    end,
})

-- При переході в режим команд (:, /, ?) скидаємо на 'us' 
vim.api.nvim_create_autocmd("CmdlineEnter", {
    group = group,
    callback = function()
        set_layout("us")
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
