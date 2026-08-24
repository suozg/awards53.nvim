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
        -- рисует вертикальние полоси которие показивают отступи кода слева
        event = { "BufReadPost", "BufNewFile" },
        main = "ibl",

        opts = {
            indent = {
                char = "│",
            },

            viewport_buffer = {
                min = 0,
                max = 200,
            },

            scope = {
                enabled = false,
            },

            whitespace = {
                remove_blankline_trail = true,
            },

            exclude = {
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
