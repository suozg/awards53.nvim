local M = {}

local state = require("awards53.state")

function M.render()
    local left = string.format(" ЗАПИС %d (із %d) ", state.index(), state.count())
    local right = " 2026, Холодов О.В. [github.com/suozg] "
    
    local width = vim.api.nvim_win_get_width(0)
    local left_len = vim.fn.strdisplaywidth(left)
    local right_len = vim.fn.strdisplaywidth(right)
    
    local spaces_count = math.max(1, width - left_len - right_len)

    return { left .. string.rep(" ", spaces_count) .. right }
end

return M
