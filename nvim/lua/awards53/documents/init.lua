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
        -- Awards53 (Генерація таблиці + Паралельний Org + Індивідуальні нагородні листи)
        -------------------------------------------------------
        if mode == "awards" then
            local output_dir = vim.fn.getcwd()
            local timestamp = os.date("%Y%m%d_%H%M")
            
            -- Ім'я для головного табличного ODT
            local odt_output_name = string.format("%s_%s.odt", tpl.id, timestamp)
            -- Ім'я для паралельного Org (лист)
            local org_output_name = string.format("%s_%s_letter.org", tpl.id, timestamp)

            -- Створюємо загальний ODT з таблицею
            require("awards53.documents.converter").compile_to_odt({
                template = tpl,
                awards_data = awards_data,
                output_dir = output_dir,
                output_name = odt_output_name,
            })

            -- Генерація окремого Нагородного листа для КОЖНОЇ картки (для "orden")
            local created_award_sheets = {}
            if tpl.id == "orden" then
                local sheet_tpl_path = vim.fn.stdpath("config") .. "/templates/templates53/awards/orden/orden_sheet.odt"
                
                if vim.fn.filereadable(sheet_tpl_path) == 1 then
                    created_award_sheets = require("awards53.documents.converter").generate_award_sheets({
                        odt_path = sheet_tpl_path,
                        awards_data = awards_data,
                        output_dir = output_dir,
                    })
                else
                    vim.notify("Увага: Шаблон нагородного листа не знайдено: " .. sheet_tpl_path, vim.log.levels.WARN)
                end
            end
            
            -- Гарне сповіщення про створені документи
            vim.defer_fn(function()
                vim.cmd("redraw")
                local msg = {
                    { "Документи успішно створено:\n", "Identifier" },
                    { "• Зведений ODT: " .. odt_output_name .. "\n", "String" },
                }
                
                if #created_award_sheets > 0 then
                    table.insert(msg, { string.format("• Нагородні листи (%d шт.):\n", #created_award_sheets), "Special" })
                    for _, sheet_name in ipairs(created_award_sheets) do
                        table.insert(msg, { "   - " .. sheet_name .. "\n", "Directory" })
                    end
                end
                
                vim.api.nvim_echo(msg, true, {})
            end, 150)
            return
        end

        -------------------------------------------------------
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

return M
