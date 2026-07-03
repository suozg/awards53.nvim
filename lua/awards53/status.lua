local M = {}

local state = require("awards53.state")

function M.render()

    return {
        string.format(
            " Картка %d/%d   %s   h l   j k   [[ ]]   ^B ^F   Ns   i   q",
            state.index(),
            state.count(),
            state.mode()
        )
    }

end

return M
