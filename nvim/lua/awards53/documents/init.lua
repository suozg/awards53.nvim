local M = {}

local context = require("awards53.documents.context")

function M.open()

    local mode = context.mode()
    local awards_data = context.awards_data()
    local picker_mode

    if mode == "awards" then
        picker_mode = "awards"
    else
        picker_mode = "documents"
    end
    require("awards53.documents.terminal").pick(picker_mode, function(path)
        if not path then
            return
        end

        local tpl = require("awards53.documents.templates").find(path, picker_mode)
        if not tpl then
            vim.notify("Обраний шаблон пошкоджений!", vim.log.levels.ERROR)
            return
        end

        -------------------------------------------------------
        -- Awards53
        -------------------------------------------------------
        if mode == "awards" then
            require("awards53.documents.converter").compile_to_odt({
                template = tpl,
                awards_data = awards_data,
                output_dir = vim.fn.getcwd(),
                output_name = tpl.id .. ".odt",
            })
            return
        end

        -------------------------------------------------------
        -- Существующий Org
        -------------------------------------------------------
        if mode == "org" then
            require("awards53.documents.converter").compile_to_odt({
                org_file = vim.api.nvim_buf_get_name(0),
            })
            return
        end

        -------------------------------------------------------
        -- Новый документ
        -------------------------------------------------------
        if mode == "new" then
            local file = require("awards53.documents.creator").create_document(tpl)

            if not file then
                return
            end

            require("awards53.documents.editor").open(file)
            return
        end

        vim.notify("Невідомий режим Documents53", vim.log.levels.ERROR)

    end)
end

vim.api.nvim_create_user_command(
    "Document53Convert",
    function()
        require("awards53.documents.converter").convert_current()
    end,
    {
        desc = "Конвертувати поточний Org-mode документ у ODT",
    }
)

return M
