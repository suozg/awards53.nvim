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

    local out = {}

    table.insert(out, "<table border='1' style='border-collapse:collapse;'>")

    -- Заголовок
    table.insert(out, "<tr>")

    for _, h in ipairs(headers) do
        table.insert(out, "<th>" .. esc(h) .. "</th>")
    end

    table.insert(out, "</tr>")

    -- Данные
    for _, rec in ipairs(records) do

        table.insert(out, "<tr>")

        for _, h in ipairs(headers) do

            table.insert(out, "<td valign='top'>")

            local value = rec[h] or {}

            for _, line in ipairs(value) do
                if line == "" then
                    table.insert(out, "<br>")
                else
                    table.insert(out, esc(line) .. "<br>")
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
