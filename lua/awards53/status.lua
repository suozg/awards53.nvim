local M = {}

local state = require("awards53.state")

function M.render()

    -- Перевіряємо, чи були зміни. Якщо так, додаємо "[+]", інакше — порожній рядок.
    local modified = state.is_changed and " [+]" or ""

    return string.format(
        " Картка %d/%d%s   %s   h l j k [[ ]] ^B ^F Ns i q             A O R X",
        state.index(),
        state.count(),
        modified,
        state.mode()
    )

end

return M
