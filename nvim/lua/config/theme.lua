-- Визначаємо фон на основі наявності файлу ~/.lightmode

-- Застосовуємо тему gruvbox
vim.cmd("colorscheme gruvbox")

vim.api.nvim_create_autocmd({ "ColorScheme", "VimEnter" }, {
    pattern = "*",
    callback = function()
        local theme_file = vim.fn.expand("~/.lightmode")
        -- колір HelpBar для Orgagenda как строка состояния Vim
        --vim.api.nvim_set_hl(0, 'OrgHelpBar', { link = 'StatusLine' })
        if vim.fn.filereadable(theme_file) == 1 then
            vim.o.background = "light"
            -- колір HelpBar для світлого режиму (закоментувати строку до if) 
            vim.api.nvim_set_hl(0, 'OrgHelpBar', { fg = '#7c6f64', bg = '#ebdbb2', bold = true }) 
        else
            vim.o.background = "dark"
            -- колір HelpBar для ntvyjuj режиму (закоментувати строку до if) 
            vim.api.nvim_set_hl(0, 'OrgHelpBar', { fg = '#bdae93', bg = '#3c3836', bold = true })
        end

        vim.cmd([[
            highlight SpellBad   gui=NONE cterm=NONE guifg=#cc241d ctermfg=124
            highlight SpellCap   gui=NONE cterm=NONE guifg=#d79921 ctermfg=172
            highlight SpellLocal gui=NONE cterm=NONE guifg=#458588 ctermfg=66
            highlight SpellRare  gui=NONE cterm=NONE guifg=#b16286 ctermfg=132
        ]])
    end,
})

