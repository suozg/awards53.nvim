local M = {}

local cfg = require("awards53")

local ns_id = vim.api.nvim_create_namespace("awards53_rnokpp")

function M.highlight_rnokpp_in_buf(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
    
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local weights = { -1, 5, 7, 9, 4, 6, 10, 5, 7 }

    -- Стиль: білий текст на червоному фоні (можна bg змінити на nil, якщо треба ТІЛЬКИ червоний текст)
    vim.api.nvim_set_hl(0, "Awards53RnokppError", { fg = "#FFFFFF", bg = "#FF0000", bold = true })

    for line_idx, line in ipairs(lines) do
        local start_pos = 1
        while start_pos <= #line do
            local init_match, end_match = line:find("%d%d%d%d%d%d%d%d%d%d", start_pos)
            if not init_match then break end

            local before = line:sub(init_match - 1, init_match - 1)
            local after = line:sub(end_match + 1, end_match + 1)
            
            if not before:match("%d") and not after:match("%d") then
                local match = line:sub(init_match, end_match)
                local digits = {}
                for i = 1, 10 do 
                    table.insert(digits, tonumber(match:sub(i, i))) 
                end

                local k1 = 0
                for i = 1, 9 do 
                    k1 = k1 + (digits[i] * weights[i]) 
                end
                local checksum = k1 % 11
                if checksum == 10 then checksum = 0 end

                if checksum ~= digits[10] then
                    vim.api.nvim_buf_add_highlight(buf, ns_id, "Awards53RnokppError", line_idx - 1, init_match - 1, end_match)
                end
                start_pos = end_match + 1
            else
                start_pos = init_match + 1
            end
        end
    end
end

function M.is_section(line)
    -- Чітко шукаємо рядок, що починається з зірочки та має назву секції (AWARDS53)
    local section = vim.pesc(cfg.config.section)
    return line:match("^%*%s+" .. section .. "%s*$") ~= nil
end

function M.is_heading(line)
    -- Будь-який інший заголовок Org-mode (наприклад, "* Наступний розділ" або "** Підрозділ")
    if line:match("^%*+%s+") then
        return not M.is_section(line)
    end
    return false
end

function M.normalize(text)
    return vim.fn.tolower(vim.trim(text))
end

function M.info(msg)
    vim.notify(msg, vim.log.levels.INFO)
end

function M.warn(msg)
    vim.notify(msg, vim.log.levels.WARN)
end

function M.error(msg)
    vim.notify(msg, vim.log.levels.ERROR)
end

return M
