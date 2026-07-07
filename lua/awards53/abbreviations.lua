local M = {}

-- Словник точних відповідностей скорочень
local dictionary = {
    -- 3 Армійський Корпус
    ["3АКого"]   = "3 армійського корпусу",
    ["3АКу"]     = "3 армійському корпусу",
    ["3АК"]      = "3 армійський корпус",
    
    -- 53 ОМБр
    ["53ОМБРої"] = "53 окремої механізованої бригади",
    ["53ОМБРі"]  = "53 окремій механізованій бригаді",
    ["53ОМБР"]   = "53 окрема механізована бригада",
}

-- Функція для розгортання скорочень в одному рядку
function M.expand_text(text)
    if not text or text == "" then return text end

    -- Сортуємо ключі за довжиною (від довших до коротших),
    -- щоб "3АКого" не перетворилося на "3 армійський корпусого"
    local keys = {}
    for k in pairs(dictionary) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return #a > #b end)
    
    for _, key in ipairs(keys) do
        -- %f[%w_] та %f[%W_] гарантують заміну цілого слова, а не частини іншого тексту
        local pattern = "%f[%w_]" .. vim.pesc(key) .. "%f[%W_]"
        text = text:gsub(pattern, dictionary[key])
    end
    
    return text

end

-- Функція для обробки масиву рядків поля
function M.expand_lines(lines)
    if type(lines) ~= "table" then return lines end
    local out = {}
    for _, line in ipairs(lines) do
        table.insert(out, M.expand_text(line))
    end
    return out
end

return M
