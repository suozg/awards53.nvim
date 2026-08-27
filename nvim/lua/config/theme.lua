-- Застосовуємо тему gruvbox
vim.cmd("colorscheme gruvbox")

vim.api.nvim_create_autocmd({ "ColorScheme", "VimEnter" }, {
    pattern = "*",
    callback = function()
        local theme_file = vim.fn.expand("~/.lightmode")
        -- Визначаємо колір на основі наявності файлу ~/.lightmode
        if vim.fn.filereadable(theme_file) == 1 then
            vim.o.background = "light"
            vim.api.nvim_set_hl(0, 'OrgHelpBar', {
                fg = '#7c6f64', 
                bg = '#ebdbb2',
            })
            -- затемнення неактивного буфера 
            vim.api.nvim_set_hl(0, "DimWindow", { bg = "#717171" })
            -- orgmode help bar
            vim.api.nvim_set_hl(0, "OrgHelpKey", {
                fg = "#b57614",
                bg = "#ebdbb2",
                bold = true,
            })

            vim.api.nvim_set_hl(0, "OrgHelpText", {
                fg = "#7c6f64",
                bg = "#ebdbb2",
            })

            vim.api.nvim_set_hl(0, "OrgHelpSep", {
                fg = "#a89984",
                bg = "#ebdbb2",
            })
            
        else
            vim.o.background = "dark"
            vim.api.nvim_set_hl(0, 'OrgHelpBar', { 
                fg = '#bdae93', 
                bg = '#3c3836' 
            })
            -- затемнення неактивного буфера
            vim.api.nvim_set_hl(0, "DimWindow", { bg = "#3c3836" })

            -- orgmode help bar
            vim.api.nvim_set_hl(0, "OrgHelpKey", {
                fg = "#d79921",
                bg = "#3c3836",
                bold = true,
            })

            vim.api.nvim_set_hl(0, "OrgHelpText", {
                fg = "#bdae93",
                bg = "#3c3836",
            })

            vim.api.nvim_set_hl(0, "OrgHelpSep", {
                fg = "#665c54",
                bg = "#3c3836",
            })
        end
        
        -- подсветка синтаксиса 
        vim.cmd([[
            highlight SpellBad   gui=NONE cterm=NONE guifg=#cc241d ctermfg=124
            highlight SpellCap   gui=NONE cterm=NONE guifg=#d79921 ctermfg=172
            highlight SpellLocal gui=NONE cterm=NONE guifg=#458588 ctermfg=66
            highlight SpellRare  gui=NONE cterm=NONE guifg=#b16286 ctermfg=132
        ]])
    end,
})

-- Автоматичне затемнення неактивних вікон у Neovim
vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
    callback = function()
        vim.wo.winhighlight = "Normal:Normal,NormalNC:DimWindow"
    end,
})

