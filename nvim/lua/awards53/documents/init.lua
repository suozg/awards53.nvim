local M = {}

function M.open()
    require("awards53.documents.terminal").pick(function(path)

        if not path then return end

        local tpl = require("awards53.documents.templates").find(path)
        if not tpl then
            vim.notify("Обраний шаблон пошкоджений (відсутній .org)!", vim.log.levels.ERROR)
            return
        end

        local file = require("awards53.documents.creator").create(tpl)
        if not file then return end

        require("awards53.documents.editor").open(file)

    end)
end

-- Реєструємо глобальну команду користувача :Document53Convert
vim.api.nvim_create_user_command(
    "Document53Convert",
    function()
        require("awards53.documents.converter").compile_to_odt()
    end,
    {
        desc = "Конвертувати поточний Org-mode документ у ODT за допомогою шаблону",
    }
)

return M
