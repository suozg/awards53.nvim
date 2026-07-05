local M = {}

local state = require("awards53.state")

function M.render()

    return {
        string.format(
            " ЗАПИС %d із %d",
            state.index(),
            state.count()
        )
    }

end

return M
