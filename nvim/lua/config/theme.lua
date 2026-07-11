-- =============================================================================
-- 4. ТЕМА ТА ВІЗУАЛІЗАЦІЯ
-- =============================================================================
vim.api.nvim_set_hl(0, 'SpellBad', { undercurl = true, sp = 'Red', fg = 'Red' })
vim.api.nvim_set_hl(0, 'SpellCap', { undercurl = true, sp = 'Brown', fg = 'Brown' })

local function set_theme(mode)
    local gruvbox_exists = vim.fn.filereadable(vim.fn.expand("~/.config/nvim/colors/gruvbox.vim")) == 1
    if gruvbox_exists then
        vim.g.gruvbox_italic = 1
        vim.g.gruvbox_bold = 1
        if mode == "dark" then
            vim.o.background = "dark"
            vim.g.gruvbox_contrast_dark = 'hard'
        else
            vim.o.background = "light"
            vim.g.gruvbox_contrast_light = 'soft'
            vim.cmd("colorscheme gruvbox")
            -- Кастомні кольори для світлої теми
            local hl = vim.api.nvim_set_hl
            hl(0, 'Normal', { bg = '#E3E2CF' })
            hl(0, 'NormalFloat', { bg = '#E3E2CF' })
            hl(0, 'LineNr', { bg = '#E3E2CF', fg = '#7c6f64' })
            hl(0, 'SignColumn', { bg = '#E3E2CF' })
            hl(0, 'EndOfBuffer', { bg = '#E3E2CF' }) 
            return
        end
        vim.cmd("colorscheme gruvbox")
    else
        vim.o.background = "dark"
        vim.cmd("colorscheme desert")
    end
end

local theme_file = vim.fn.expand("~/.lightmode")
if vim.fn.filereadable(theme_file) == 1 then
    local mode = vim.fn.trim(vim.fn.readfile(theme_file)[1])
    set_theme(mode)
else
    set_theme("dark")
end


