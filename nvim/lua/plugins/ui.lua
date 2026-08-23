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

    {
        "echasnovski/mini.nvim",
        version = false,
        event = { "BufReadPost", "BufNewFile" },
        config = function()
            -- 1. Підключаємо модулі курсора та таблайну
            require("mini.cursorword").setup()
            
            require("mini.tabline").setup({
                show_icons = true,
                tabpage_section = "left",
            })

            -- 2. Налаштовуємо mini.notify для виведення в правому верхньому кутку
            require("mini.notify").setup({
                window = {
                    max_width_share = 0.382,
                    winblend = 25,
                    config = function()
                        return {
                            anchor = "NE", -- північний схід (правий верхній кут)
                            relative = "editor",
                            row = 1,       -- відступ зверху
                            col = vim.o.columns - 1, -- відступ справа
                        }
                    end,
                },
            })

            -- 3. Перенаправляємо стандартний vim.notify на двигун mini.notify
            -- та збільшуємо час показу повідомлень (у мілісекундах)
            -- 10000 мс = 10 секунд, 15000 мс = 15 секунд
            vim.notify = require("mini.notify").make_notify({
                INFO  = { duration = 10000 },
                WARN  = { duration = 10000 },
                ERROR = { duration = 15000 },
            })

            -- 3. Гарячі клавіші для буферів (виправлено "[b>" на "[b")
            vim.keymap.set("n", "]b", "<cmd>bnext<CR>", { desc = "Наступний буфер", silent = true })
            vim.keymap.set("n", "[b", "<cmd>bprevious<CR>", { desc = "Попередній буфер", silent = true })
            
            vim.keymap.set("n", "<leader>bn", "<cmd>bnext<CR>", { desc = "Наступний буфер", silent = true })
            vim.keymap.set("n", "<leader>bp", "<cmd>bprevious<CR>", { desc = "Попередній буфер", silent = true })
            vim.keymap.set("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Закрити буфер", silent = true })
        end,
    },
    
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
