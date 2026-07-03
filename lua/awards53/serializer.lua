local M = {}

function M.build(data)

    local out = {}
    table.insert(out, "")
    
    for i, record in ipairs(data.records) do

        for _, field in ipairs(data.headers) do

            table.insert(out, field .. "::")

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
            table.insert(out, "===")
            table.insert(out, "")
        end

    end

    return out

end

return M
