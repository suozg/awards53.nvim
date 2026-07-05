local M = {}

local function esc(s)
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    return s
end

function M.html(data)

    local headers = data.headers
    local records = data.records

    local out = table.create and table.create(#records * #headers + 10) or {}

    -- Стилизуем таблицу: тонкая внешняя граница, стандартный шрифт
    table.insert(out, "<table style='border-collapse: collapse; width: 100%; font-family: sans-serif; font-size: 14px; border: 1px solid #cbd5e1;'>")

    -- Заголовок таблицы (без фоновой заливки)
    table.insert(out, "<tr>")

    for _, h in ipairs(headers) do
        table.insert(out, "<th style='border: 1px solid #cbd5e1; padding: 10px; text-align: left; font-weight: 600;'>" .. esc(h) .. "</th>")
    end

    table.insert(out, "</tr>")

    -- Данные таблицы
    for _, rec in ipairs(records) do

        table.insert(out, "<tr>")

        for _, h in ipairs(headers) do

            table.insert(out, "<td valign='top' style='border: 1px solid #e2e8f0; padding: 8px; max-width: 300px; word-wrap: break-word;'>")

            local value = rec[h] or {}

            -- 1. Находим первую непустую строку (пропускаем пустые строки в начале)
            local first_non_empty = 0
            for i = 1, #value do
                if vim.trim(value[i]) ~= "" then
                    first_non_empty = i
                    break
                end
            end

            -- 2. Находим последнюю непустую строку (пропускаем пустые строки в конце)
            local last_non_empty = 0
            for i = #value, 1, -1 do
                if vim.trim(value[i]) ~= "" then
                    last_non_empty = i
                    break
                end
            end

            -- Если в поле есть хоть какой-то текст, выводим строго этот диапазон
            if first_non_empty > 0 and last_non_empty >= first_non_empty then
                for i = first_non_empty, last_non_empty do
                    local line = value[i]
                    if vim.trim(line) == "" then
                        table.insert(out, "<br>")
                    else
                        table.insert(out, esc(line) .. "<br>")
                    end
                end
            end

            table.insert(out, "</td>")

        end

        table.insert(out, "</tr>")

    end

    table.insert(out, "</table>")

    return table.concat(out, "\n")
end

return M
