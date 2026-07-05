local M = {}

function M.build(data)

    local cfg = require("awards53")
    local out = {}
    table.insert(out, "")
    
    for i, record in ipairs(data.records) do

        for _, field in ipairs(data.headers) do
            table.insert(out, field .. cfg.config.separator)
            local value = record[field] or {}

            if type(value) == "table" then
                for _, line in ipairs(value) do
                    table.insert(out, line)
                end
            else
                table.insert(out, tostring(value))
            end

            table.insert(out, "")

        end

        if i < #data.records then
            table.insert(out, cfg.config.record_separator)
            table.insert(out, "")
        end

    end

    -- заміна «ялинок» на подвійні лапки 
    for i, line in ipairs(out) do
        out[i] = line:gsub("«", '"'):gsub("»", '"')
    end

    return out

end

return M
