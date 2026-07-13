local M = {}

local parser = require("awards53.parser")
local state = require("awards53.state")

local function has_doc53_marker(buf)
        buf = buf or 0

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

        for _, line in ipairs(lines) do
            if line:match("^#%+ODT_STYLES_FILE:") then
                return true
            end
        end

        return false
    end


function M.awards_data()
    -- Если интерфейс Awards53 уже загружен
    if state.records and #state.records > 0 then
        return state.data()
    end

    -- Иначе ищем открытый буфер Awards53
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
            local first = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""

            if first == "* AWARDS53" then
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

    -- Awards53 имеет наивысший приоритет
    if M.awards_data() then
        return "awards"
    end

    -- Документ Documents53 определяется по маркеру
    if has_doc53_marker() then
        return "org"
    end

    -- Всё остальное считается новым документом
    return "new"
end

return M
