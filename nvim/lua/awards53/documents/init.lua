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
        -- Awards53 (Генерація таблиці + Паралельний Org з часом)
        -------------------------------------------------------
        if mode == "awards" then
            local output_dir = vim.fn.getcwd()
            
            -- Формуємо часову мітку (наприклад: 20260720_1940)
            local timestamp = os.date("%Y%m%d_%H%M")
            
            -- Базове ім'я файлу на основі шаблону та часу (напр., templateId_20260720_1940)
            local base_name = string.format("%s_%s", tpl.id, timestamp)
            
            local odt_output_name = base_name .. ".odt"
            local org_output_name = base_name .. ".org"

            -- 1. Спершу створюємо паралельний текстовий .org з потрібним ім'ням
            -- Передаємо org_output_name як третій аргумент
            require("awards53.documents.converter").create_parallel_org(awards_data, output_dir, org_output_name)

            -- 2. Потім штатно запускаємо збірку ODT з таблицею
            require("awards53.documents.converter").compile_to_odt({
                template = tpl,
                awards_data = awards_data,
                output_dir = output_dir,
                output_name = odt_output_name,
            })
            
            -- Повертаємо гарне сповіщення на екран
            vim.defer_fn(function()
                vim.cmd("redraw")
                vim.api.nvim_echo({
                    { "Документи успішно створено у: ", "Identifier" },
           { odt_output_name, "String" },
                    { " та ", "Normal" },
                    { org_output_name, "String" }
                }, true, {})
            end, 150)
            return
        end
        
        -- -------------------------------------------------------
        -- Існуючий Org
        -------------------------------------------------------
        if mode == "org" then
            require("awards53.documents.converter").compile_to_odt({
                org_file = vim.api.nvim_buf_get_name(0),
            })
            return
        end

        -------------------------------------------------------
        -- Новий документ
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
