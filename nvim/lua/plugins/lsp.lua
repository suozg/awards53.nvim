return {
    {
        "neovim/nvim-lspconfig",
        event = { "BufReadPre", "BufNewFile" },
    },

    {
        "williamboman/mason.nvim",
        cmd = "Mason",
        config = function()
            require("mason").setup()
        end,
    },

    {
        "williamboman/mason-lspconfig.nvim",
            lazy = true,
            dependencies = {
            "williamboman/mason.nvim",
        },

        config = function()

            local servers = {
                "lua_ls",
                "pyright",
                "ts_ls",
                "bashls",
            }

            require("mason-lspconfig").setup({
                ensure_installed = servers,
            })

            local capabilities =
                require("cmp_nvim_lsp").default_capabilities()

            for _, server in ipairs(servers) do
                vim.lsp.config(server, {
                    capabilities = capabilities,
                })

                vim.lsp.enable(server)
            end

        end,
    },

    {
        "hrsh7th/nvim-cmp",
        event = "InsertEnter",
        dependencies = {
            "hrsh7th/cmp-buffer",
            "hrsh7th/cmp-path",
            "hrsh7th/cmp-nvim-lsp",
            "L3MON4D3/LuaSnip",
            "saadparwaiz1/cmp_luasnip",
        },

        config = function()

            local cmp = require("cmp")
            local luasnip = require("luasnip")

            cmp.setup({

                snippet = {
                    expand = function(args)
                        luasnip.lsp_expand(args.body)
                    end,
                },
                completion = {
                    autocomplete = false,
                },
                mapping = cmp.mapping.preset.insert({

                    ["<C-l>"] = cmp.mapping.complete(), -- открыть меню вручную
                    ["<C-e>"] = cmp.mapping.abort(),    -- ЗАКРИТИ МЕНЮ 
                    ["<CR>"] = cmp.mapping.confirm({
                        select = true,
                    }),

                }),

                sources = {
                    { name = "nvim_lsp" },

                    {
                        name = "buffer",
                        option = {
                            keyword_pattern = [[[^%s]\+]],
                        },
                    },

                    { name = "path" },
                },

            })

        end,
    },

}
