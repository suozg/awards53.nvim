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

    -- Реєстрація базових команд
    require("awards53.commands").setup()
    
    vim.api.nvim_create_user_command("Documents53", function()
        require("awards53.documents").open() -- шлях до модуля документів
    end, {})

    -- Автовизначення типу файлу при відкритті
    vim.api.nvim_create_autocmd("BufReadPost", {
        callback = function(args)
            vim.schedule(function()
                if not vim.api.nvim_buf_is_valid(args.buf) then
                    return
                end

                -- Зчитуємо перші кілька рядків для перевірки наявності маркерів
                local lines = vim.api.nvim_buf_get_lines(args.buf, 0, 15, false)
                if #lines == 0 then return end

                ----------------------------------------------------------------
                -- 1. Перевірка на базу даних Awards53
                ----------------------------------------------------------------
                if lines[1] and utils.is_section(lines[1]) then
                    vim.api.nvim_set_current_buf(args.buf)
                    vim.cmd("Awards53")
                    
                    -- Після успішного відкриття карток беремо перше ліпше поле 
                    -- файлу як дефолтне для швидкого пошуку (клавіша /) та сортування (клавіша S)
                    local headers = state.headers_list()
                    if #headers > 0 and M.config.default_sort == "" then
                        M.config.default_sort = headers[1]
                    end
                    return
                end

                ----------------------------------------------------------------
                -- 2. Перевірка на документ Documents53 (Org-mode)
                ----------------------------------------------------------------
                local is_doc53 = false
                for _, line in ipairs(lines) do
                    if line:match("^#%+ODT_STYLES_FILE:") or line:match("^#%+DOC53_REQUIRED:") then
                        is_doc53 = true
                        break
                    end
                end

                if is_doc53 then
                    -- Вмикаємо захист службових полів (приховування та відновлення при спробі видалити)
                    pcall(function()
                        require("awards53.documents.editor").protect_tech_lines(args.buf)
                    end)
                    
                    -- Підключаємо аббревіатури
                    pcall(function()
                        require("awards53.abbreviations").register_buffer_abbreviations(args.buf)
                    end)

                    -- Реєструємо команду швидкої конвертації локально для цього буфера
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
