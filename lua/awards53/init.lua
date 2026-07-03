local M = {}

local defaults = {
    separator = "::",
}

M.config = {}

function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", defaults, opts or {})

    require("awards53.commands").setup()
end

return M
