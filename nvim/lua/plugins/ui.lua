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
            -- Підключаємо модулі курсора та таблайну
            require("mini.cursorword").setup()
            require("mini.surround").setup() -- модуль для керування лапками та дужками:
            
            require("mini.tabline").setup({
                show_icons = true,
                tabpage_section = "left",
            })
            
            -- Налаштовуємо вигляд mini.notify
            require("mini.notify").setup({
                content = {
                    -- Форматуємо текст сповіщення, додаючи іконку на початку
                    format = function(notif)
                        local icons = {
                            ERROR = '❌ ',
                            WARN  = '⚠️ ',
                            INFO  = '💡 ',
                        }
                        local icon = icons[notif.level] or '💡 '
                        
                        return icon .. notif.msg
                    end,
                },
                window = {
                    max_width_share = 0.382,
                    winblend = 25,
                    config = function()
                        return {
                            anchor = "SW",
                            relative = "editor",
                            row = vim.o.lines - 2,
                            col = 1,
                            border = 'single',
                            title = '', -- заголовок вікна рамки
                            title_pos = 'left',
                        }
                    end,
                },
                -- Налаштування анімації/таймінгів 
                animation = function(notif)
                    -- Повертаємо таблицю з нульовою затримкою або вимикаємо ефекти
                    return {
                        {
                            opacity = 100,
                            precision = 100,
                        }
                    }
                end,
            })
            -- Перенаправляємо стандартний vim.notify на двигун mini.notify
            -- 15000 = 15 секунд
            vim.notify = require("mini.notify").make_notify({
                INFO  = { duration = 10000 },
                WARN  = { duration = 15000 },
                ERROR = { duration = 30000 },
            })

            -- Перевизначаємо підсвічування для зміненої вкладки в mini.tabline
            -- Наприклад: зелений фон (#98c379) і чорний текст (#000000) для активної або неактивної вкладки
            vim.api.nvim_set_hl(0, "MiniTablineModifiedCurrent", { fg = "#000000", bg = "#739313" })
            vim.api.nvim_set_hl(0, "MiniTablineModifiedVisible", { fg = "#000000", bg = "#739313" })
            vim.api.nvim_set_hl(0, "MiniTablineModifiedHidden",  { fg = "#739313", bg = "NONE", italic = true })
            -- Гарячі клавіші для буферів (виправлено "[b>" на "[b")
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
