local M = {}

local state = require("awards53.state")

local function hr(target_width)
    local pattern = ". . "
    local pattern_len = #pattern
    local count = math.ceil(target_width / pattern_len)
    return string.sub(string.rep(pattern, count), 1, target_width)
end

function M.render()
    local lines = {}
    local ranges = {}

    local record = state.current_record()
    if not record then
        return lines, ranges
    end

    local headers = state.headers_list()
    local current_field = state.field_name()
    local indent = "    "

    table.insert(lines, "")

    for i, field in ipairs(headers) do
        local is_active = (field == current_field)
        local value = record[field] or {}
        local value_lines = {}

        if type(value) == "table" then
            value_lines = value
        else
            value_lines = { tostring(value) }
        end

        if is_active then
            local total_fields = #headers
            local header_text = string.format(
                " 󰓻 Поле %s/%d     j▲ k▼ #f    🖊:i► inline / I► editor    ⇊:J/K    B 0    ",
                field,
                total_fields
            )

            table.insert(lines, "")
            table.insert(lines, header_text)

            local start_row = #lines

            if #value_lines == 0 then
                table.insert(lines, indent .. "")
            else
                for _, line in ipairs(value_lines) do
                    table.insert(lines, indent .. line)
                end
            end

            local end_row = #lines - 1

            ranges[field] = {
                start_row = start_row,
                end_row = end_row,
                indent = indent,
            }

            table.insert(lines, "")
        else
            local header_line = "[" .. field .. "]"
            table.insert(lines, header_line)

            local start_row = #lines

            if #value_lines == 0 then
                table.insert(lines, indent .. "")
            else
                for _, line in ipairs(value_lines) do
                    table.insert(lines, indent .. line)
                end
            end

            local end_row = #lines - 1

            ranges[field] = {
                start_row = start_row,
                end_row = end_row,
                indent = indent,
            }

            local current_hr_width = vim.fn.strdisplaywidth(header_line)
            table.insert(lines, hr(current_hr_width))
            table.insert(lines, "")
        end
    end

    return lines, ranges
end

return M
