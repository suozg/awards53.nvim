return {

    {
        "windwp/nvim-autopairs",
        -- Завантажуємо лише тоді, коли переходимо в режим вставки
        event = "InsertEnter",
        config = function()
            require("nvim-autopairs").setup({})
        end,
    },

    {
        "lukas-reineke/indent-blankline.nvim",
        -- Завантажуємо лише при відкритті файлів
        event = { "BufReadPost", "BufNewFile" },
        main = "ibl", -- Обов'язково для нової версії v3
        opts = {
            indent = {
                char = "│", -- Ваша вертикальна лінія
            },
            whitespace = {
                -- Замість show_trailing_blankline_indent:
                remove_blankline_trail = true, 
            },
            exclude = {
                -- Замість filetype_exclude:
                filetypes = {
                    "help",
                    "terminal",
                    "dashboard",
                    "fzf",
                    "lspinfo",
                    "packager",
                },
            },
        },
    },

}
