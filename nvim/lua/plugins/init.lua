return {

    -- FZF
    {
        "junegunn/fzf",
        build = "./install --all",
        lazy = true, 
    },
    {
        "junegunn/fzf.vim",
        dependencies = { "junegunn/fzf" },
        -- Пропишіть сюди команди, які ви найчастіше використовуєте:
        cmd = { "Files", "GFiles", "Buffers", "Rg", "BLines", "History" },
    },
    -- Editor
    {
        "tpope/vim-commentary",
        event = { "BufReadPost", "BufNewFile" },
    },
    {
        "godlygeek/tabular",
        event = { "BufReadPost", "BufNewFile" },
    },
    -- {
    --     "dhruvasagar/vim-table-mode",
    --     cmd = { "TableModeToggle", "TableModeEnable" }, -- завантажиться тільки коли викличете команду
    --     -- або альтернативно: event = { "BufReadPost", "BufNewFile" }
    -- },
    
    -- UI
    { import = "plugins.ui" },

    -- Treesitter
    {
        "nvim-treesitter/nvim-treesitter",
        event = { "BufReadPost", "BufNewFile" },
        build = ":TSUpdate",

        opts = {
            highlight = {
                enable = true,
                additional_vim_regex_highlighting = { "org" },
            },
        },
    },

    -- Org
    { import = "plugins.orgmode" },

    -- LSP
    { import = "plugins.lsp" },

    -- Editor plugins
    { import = "plugins.editor" },
}
