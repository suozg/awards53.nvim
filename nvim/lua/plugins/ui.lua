return {

    {
        "nvim-tree/nvim-web-devicons",
        lazy = true,
    },

    {
        "lewis6991/gitsigns.nvim",
            event = { "BufReadPost", "BufNewFile" },
            config = function()
            require("gitsigns").setup()
        end,
    },

    -- -- {
    --     "akinsho/bufferline.nvim",
    --         version = "*",
    --         dependencies = { "nvim-tree/nvim-web-devicons" }, -- Іконки для вкладок
    --         config = function()
    --     end,
    -- },
    -- {
    --     "echasnovski/mini.nvim",
    --     version = false,
    --     event = { "BufReadPost", "BufNewFile" },
    --     config = function()
    --         require("mini.cursorword").setup()
    --     end,
    -- },

    {
        "nvimdev/dashboard-nvim",
        event = "VimEnter",
        dependencies = {
            "nvim-tree/nvim-web-devicons",
        },

        config = function()
            require("dashboard").setup({
                theme = "hyper",
                config = {
                    week_header = {
                        enable = true,
                    },

                    shortcut = {
                        {
                            desc = "󰈞 Find File (FZF)",
                            group = "@property",
                            action = "Files",
                            key = "f",
                        },
                        {
                            desc = "󱎘 Recent Files (Недавні)",
                            group = "@constructor",
                            action = "History",
                            key = "r",
                        },
                        {
                            desc = "󰱼 Find Text (RipGrep)",
                            group = "@string",
                            action = "Rg",
                            key = "g",
                        },
                        {
                            desc = " New File",
                            group = "@keyword",
                            action = "ene | startinsert",
                            key = "n",
                        },
                    },

                    project = {
                        enable = false,
                    },

                    mru = {
                        limit = 20,
                        icon = "󰈚 ",
                        label = "Недавні файли:",
                    },

                    footer = {
                        "Швидкий старт Neovim",
                    },
                },
            })
        end,
    },

}
