local M = {}

local state = require("awards53.state")

function M.render()

    -- Перевіряємо, чи були зміни. Якщо так, додаємо "[+]", інакше — порожній рядок.
    local modified = state.is_changed and " [+]" or ""

    return string.format(
        " Картка %d/%d%s   %s    h◄ l► [[◀◀ ]]▶▶ N q⏏     A dd y p ",
        state.index(),
        state.count(),
        modified,
        state.mode()
    )

end

return M
