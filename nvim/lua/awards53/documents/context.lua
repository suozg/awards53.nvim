local M = {}

local parser = require("awards53.parser")
local state = require("awards53.state")

-- Перевіряє, чи містить буфер або файл ознаки текстового документа Documents53
local function is_text_document(buf)
    buf = buf or 0
    if not vim.api.nvim_buf_is_valid(buf) then return false end

    local lines = vim.api.nvim_buf_get_lines(buf, 0, 10, false) -- беремо перші 10 рядків для надійності
    for _, line in ipairs(lines) do
        if line:match("^#%+ODT_STYLES_FILE:") or line:match("^#%+DOC53_REQUIRED:") then
            return true
        end
    end
    return false
end

function M.awards_data()
    -- Якщо інтерфейс Awards53 вже завантажений
    if state.records and #state.records > 0 then
        return state.data()
    end

    -- Шукаємо відкритий буфер з базою даних Awards53
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
            local first = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""

            -- База даних завжди починається строго з "* AWARDS53"
            if first:match("^%*%s*AWARDS53") then
                local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                local block = {}

                for i = 2, #lines do
                    if lines[i]:match("^%*+%s+") then
                        break
                    end
                    table.insert(block, lines[i])
                end

                local parsed = parser.parse(block)

                if parsed and #parsed.records > 0 then
                    return parsed
                end
            end
        end
    end

    return nil
end

function M.mode()
    -- 1. Перевіряємо ПОТОЧНИЙ активний буфер (0)
    if vim.api.nvim_buf_is_valid(0) then
        local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
        
        -- Якщо перший рядок поточного файлу — це база даних
        if first_line:match("^%*%s*AWARDS53") then
            return "awards"
        end

        -- Якщо поточний файл містить теги текстового шаблону (навіть якщо це .txt або .org)
        if is_text_document(0) then
            return "org"
        end
    end

    -- 2. Якщо поточний буфер не визначено, але у фоні є відкрита БД Awards53
    if M.awards_data() then
        return "awards"
    end

    -- Все інше вважаємо новим/невідомим документом
    return "new"
end

return M
