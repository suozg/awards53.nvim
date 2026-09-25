-- rnokpp.lua
local M = {}

local WEIGHTS = { -1, 5, 7, 9, 4, 6, 10, 5, 7 }

local MONTHS_UA = {
    "січня", "лютого", "березня", "квітня", "травня", "червня",
    "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"
}

--- розраховує структуру дати з перших 5 цифр РНОКПП
---@param rnokpp string
---@return table|nil
local function get_birth_table(rnokpp)
    if not rnokpp or #rnokpp ~= 10 then
        return nil
    end

    local days = tonumber(rnokpp:sub(1, 5))
    if not days then
        return nil
    end

    local base_time = os.time({ year = 1899, month = 12, day = 31, hour = 12 })
    local birth_time = base_time + (days * 86400)
    local t = os.date("*t", birth_time)

    if not t or not t.year or not t.month or not t.day then
        return nil
    end

    return t
end

--- Обчислює дату народження за РНОКПП (формат DD.MM.YYYY)
---@param rnokpp string
---@return string|nil
function M.get_birth_date(rnokpp)
    local t = get_birth_table(rnokpp)
    if not t then return nil end

    return string.format("%02d.%02d.%04d", t.day, t.month, t.year)
end

--- Обчислює дату народження за РНОКПП у текстовому форматі
---@param rnokpp string
---@return string|nil
function M.get_birth_date_formatted(rnokpp)
    local t = get_birth_table(rnokpp)
    if not t then return nil end

    return string.format("%d %s %d року", t.day, MONTHS_UA[t.month] or "", t.year)
end

--- Перевіряє валідність контрольної суми РНОКПП
---@param rnokpp string
---@return boolean
function M.is_valid(rnokpp)
    if not rnokpp or #rnokpp ~= 10 or not rnokpp:match("^%d+$") then
        return false
    end

    local k1 = 0
    for i = 1, 9 do
        local digit = tonumber(rnokpp:sub(i, i))
        k1 = k1 + (digit * WEIGHTS[i])
    end

    local checksum = k1 % 11
    if checksum == 10 then
        checksum = 0
    end

    local control_digit = tonumber(rnokpp:sub(10, 10))
    return checksum == control_digit
end

--- Шукає РНОКПП (10 цифр) у тексті
--- @param text string
--- @return string|nil code, number|nil start_idx, number|nil end_idx
function M.find_in_text(text)
    if not text or type(text) ~= "string" then 
        return nil 
    end

    local start_idx, end_idx = text:find("(%d%d%d%d%d%d%d%d%d%d)")
    if not start_idx then 
        return nil 
    end

    local code = text:sub(start_idx, end_idx)
    return code, start_idx, end_idx
end

return M
