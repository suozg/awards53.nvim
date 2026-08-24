local M = {}

local state = require("awards53.state")

function M.render()
    local left = string.format(" ЗАПИС %d із %d", state.index(), state.count())
    local right = "(c) suozg, 2026 "
    
    local width = vim.api.nvim_win_get_width(0)
    local left_len = vim.fn.strdisplaywidth(left)
    local right_len = vim.fn.strdisplaywidth(right)
    
    local spaces_count = width - left_len - right_len
    if spaces_count < 1 then
        spaces_count = 1
    end
    
    local result = left .. string.rep(" ", spaces_count) .. right

    return { result }
end

return M
