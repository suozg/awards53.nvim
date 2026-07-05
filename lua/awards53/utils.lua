local M = {}

local cfg = require("awards53")

function M.is_section(line)
    -- Отримуємо "AWARDS53" з конфігу та екрануємо спецсимволи для безпеки
    local section = vim.pesc(cfg.config.section)

    -- Шаблон шукає: початок рядка, одну або більше зірочок, 
    -- необов'язкові пробіли, а потім саме слово AWARDS53
    return line:match("^%*+%s*" .. section .. "%s*$") ~= nil
end

function M.is_heading(line)
    -- Заголовком є будь-який рядок із зірочками, що НЕ є нашою секцією AWARDS53
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
