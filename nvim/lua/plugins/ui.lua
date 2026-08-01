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
          require("mini.cursorword").setup()
          
          -- Додаємо верхню панель відкритих файлів (буферів)
          require("mini.tabline").setup({
            show_icons = true,
            tabpage_section = "left",
          })

          -- Перемикання між відкритими файлами за допомогою Tab / Shift+Tab
          vim.keymap.set("n", "]b", "<cmd>bnext<CR>", { desc = "Наступний буфер", silent = true })
          vim.keymap.set("n", "[b>", "<cmd>bprevious<CR>", { desc = "Попередній буфер", silent = true })
          -- Також можна дублювати через Leader
          vim.keymap.set("n", "<leader>bn", "<cmd>bnext<CR>", { desc = "Наступний буфер", silent = true })
          vim.keymap.set("n", "<leader>bp", "<cmd>bprevious<CR>", { desc = "Попередній буфер", silent = true })
          -- Закрити поточний файл (буфер)
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
