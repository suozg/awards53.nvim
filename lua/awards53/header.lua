local M = {}

local state = require("awards53.state")

function M.render()

    return {
        string.format(
            " НАГОРОДНИЙ ЛИСТ %d із %d",
            state.index(),
            state.count()
        )
    }

end

return M
