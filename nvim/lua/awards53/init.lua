local M = {}

local defaults = {
    separator = "::",
    section = "AWARDS53",
    default_sort = "1", -- Автоматично сортувати/шукати за першим полем
    record_separator = "===",
}

M.config = {}

function M.setup(opts)
    local utils = require("awards53.utils")
    local state = require("awards53.state")

    M.config = vim.tbl_deep_extend(
        "force",
        defaults,
        opts or {}
    )

    -- 1. Реєстрація глобальних namespace для підсвічування (оптимізація)
    M.ns_help = vim.api.nvim_create_namespace("awards53_editor_help")
    M.ns_fields = vim.api.nvim_create_namespace("awards53_fields")
    M.ns_rnokpp = vim.api.nvim_create_namespace("awards53_rnokpp")

    -- 2. Централізоване визначення кольорів та груп підсвічування
    vim.api.nvim_set_hl(0, "Awards53Help", { fg = "#897d6d", bg = "NONE" })
    vim.api.nvim_set_hl(0, "Awards53HelpText", { fg = "#897d6d", bg = "NONE", bold = false })
    vim.api.nvim_set_hl(0, "Awards53RnokppError", { fg = "#FFFFFF", bg = "#FF0000", bold = true })
    vim.cmd("highlight default link Awards53ActiveField CursorLine")

    -- 3. Реєстрація базових команд плагіна (Awards53, Awards53abbr)[cite: 9]
    require("awards53.commands").setup()
    
    -- 4. Централізована реєстрація головної глобальної команди для меню Documents53
    vim.api.nvim_create_user_command("Documents53", function()
        local status, doc_init = pcall(require, "awards53.documents.init")
        if status and doc_init and doc_init.open then
            doc_init.open()
        else
            require("awards53.documents.converter").convert_current()
        end
    end, {
        desc = "Головне меню / робота з Documents53",
    })

    -- 5. Автовизначення типу файлу при відкритті (BufReadPost)[cite: 14]
    vim.api.nvim_create_autocmd("BufReadPost", {
        callback = function(args)
            vim.schedule(function()
                if not vim.api.nvim_buf_is_valid(args.buf) then
                    return
                end

                local lines = vim.api.nvim_buf_get_lines(args.buf, 0, 15, false)
                if #lines == 0 then return end

                ----------------------------------------------------------------
                -- А. Перевірка на базу даних Awards53
                ----------------------------------------------------------------
                if lines[1] and utils.is_section(lines[1]) then
                    vim.api.nvim_set_current_buf(args.buf)
                    vim.cmd("Awards53")
                    
                    -- Реєструємо команду конвертації ЛОКАЛЬНО тільки для цього буфера
                    vim.api.nvim_buf_create_user_command(args.buf, "Document53Convert", function()
                        require("awards53.documents.converter").convert_current()
                    end, {
                        desc = "Універсальна конвертація даних Awards53",
                    })

                    local headers = state.headers_list()
                    if #headers > 0 and M.config.default_sort == "" then
                        M.config.default_sort = headers[1]
                    end
                    return
                end

                ----------------------------------------------------------------
                -- Б. Перевірка на документ Documents53 (Org-mode)[cite: 23]
                ----------------------------------------------------------------
                local is_doc53 = false
                for _, line in ipairs(lines) do
                    if line:match("^#%+ODT_STYLES_FILE:") or line:match("^#%+DOC53_REQUIRED:") then
                        is_doc53 = true
                        break
                    end
                end

                if is_doc53 then
                    -- Вмикаємо захист службових полів[cite: 26]
                    pcall(function()
                        require("awards53.documents.editor").protect_tech_lines(args.buf)
                    end)
                    
                    -- Підключаємо локальні аббревіатури для буфера[cite: 6, 26]
                    pcall(function()
                        require("awards53.abbreviations").register_buffer_abbreviations(args.buf)
                    end)

                    -- Реєструємо команду конвертації ЛОКАЛЬНО тільки для цього буфера
                    vim.api.nvim_buf_create_user_command(args.buf, "Document53Convert", function()
                        require("awards53.documents.converter").convert_current()
                    end, {
                        desc = "Конвертувати поточний Org-mode документ у ODT",
                    })
                end
            end)
        end,
    })
end

return M
