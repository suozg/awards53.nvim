local M = {}

local defaults = {
    separator = "::",
    section = "AWARDS53",
    default_sort = "ПІБ",
    record_separator = "===",
}

M.config = {}

function M.setup(opts)
    local utils = require("awards53.utils")

    M.config = vim.tbl_deep_extend(
        "force",
        defaults,
        opts or {}
    )

    require("awards53.commands").setup()

    vim.api.nvim_create_autocmd("BufReadPost", {
        callback = function(args)
            vim.schedule(function()

                if not vim.api.nvim_buf_is_valid(args.buf) then
                    return
                end

                local lines = vim.api.nvim_buf_get_lines(args.buf, 0, 5, false)
 
                if lines[1] and utils.is_section(lines[1]) then
                    vim.api.nvim_set_current_buf(args.buf)
                    vim.cmd("Awards53")
                end

            end)
        end,
    })

end

return M
