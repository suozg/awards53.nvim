local M = {}

local function is_key(line, separator)
    local pattern = "^(.-)" .. vim.pesc(separator) .. "%s*$"
    return line:match(pattern)
end

function M.parse(lines, separator)
    local cfg = require("awards53")
    local cfg = require("awards53")
    separator = separator or cfg.config.separator
    local headers = {}
    local records = {}

    local record = nil
    local current_key = nil

    local function finish_record()
        if record and next(record) ~= nil then
            table.insert(records, record)
        end
        record = {}
        current_key = nil
    end

    finish_record()

    for _, line in ipairs(lines) do
            
        if vim.trim(line) == cfg.config.record_separator then
            finish_record()

        else

            local key = is_key(line, separator)

            if key then

                current_key = vim.trim(key)

                record[current_key] = {}

                if not vim.tbl_contains(headers, current_key) then
                    table.insert(headers, current_key)
                end

            elseif current_key then

                local function is_multiline(field)
                    return field == "Текст"
                end

                if is_multiline(current_key) then
                    table.insert(record[current_key], line)
                else
                    record[current_key][1] = (record[current_key][1] or "") .. " " .. vim.trim(line)
                end

            end
        end
    end

    if next(record) ~= nil then
        table.insert(records, record)
    end

    return {
        headers = headers,
        records = records,
    }
end

return M
