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

local saved_layout = "us"

vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function()
        if saved_layout ~= "" then
            vim.fn.jobstart({ "xkb-switch", "-s", saved_layout })
            vim.fn.jobstart({ "pkill", "-RTMIN+1", "dwmblocks" })
        end
    end,
})

vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function()
        local handle = io.popen("xkb-switch -p")
        if handle then
            local current = handle:read("*l")
            handle:close()
            if current and current ~= "" then
                saved_layout = current
            end
        end

        if saved_layout ~= "us" then
            vim.fn.jobstart({ "xkb-switch", "-s", "us" })
            vim.fn.jobstart({ "pkill", "-RTMIN+1", "dwmblocks" })
        end
    end,
})

-- кольори орфографії для будь-яких тем та терміналів
vim.api.nvim_create_autocmd({ "ColorScheme", "VimEnter" }, {
    pattern = "*",
    callback = function()
        vim.api.nvim_set_hl(0, "SpellBad", { 
            fg = "Red",     -- колір тексту
            -- bg = "#928374",     -- фон
            ctermbg = "Red",    -- червоний фон у простому терміналі
            ctermfg = "White", 
            bold = true 
        })
    end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "orgagenda", }, 
  callback = function()
    vim.opt_local.colorcolumn = ""
  end,
})
