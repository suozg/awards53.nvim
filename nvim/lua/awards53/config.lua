-- lua/awards53/config.lua
local M = {}

M.options = {
    separator = "::",
    record_separator = "===",
    section = "AWARDS53",
    default_sort = "1",

    -- Директорія для файлу абревіатур
    abbreviations_dir = vim.fn.stdpath("config") .. "/awards53",
    
    -- Номер бригади для видалення цифр перед нею
    unit_number = "53",

    -- Текст, на який замінюємо
    replacement = "53 окремої механізованої бригади імені князя Володимира Мономаха 3 армійського корпусу оперативного командування \"Схід\" Сухопутних військ Збройних Cил України",

    -- Список паттернів для замін
    -- Можна додавати нові варіації написання вч/бригади без зміни коду дій
    replacement_patterns = {
        "%d+%s+окремої%s+.-%s+України",
        "військової%s+частини%s+А%d+",
    },

    officer_keywords = { 
        "лейтенант", "капітан", "майор", "підполков", "полковник", "генерал" 
    },

    documents = {
        template_dir = vim.fn.stdpath("config") .. "/templates/templates53",
        selection_file = (vim.env.XDG_RUNTIME_DIR or "/tmp") .. "/doc53-selection",
    },
}

function M.setup(user_opts)
    M.options = vim.tbl_deep_extend("force", M.options, user_opts or {})
end

return M
