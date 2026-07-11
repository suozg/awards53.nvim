local M = {}

function M.create(tpl)
    if not tpl or not tpl.org then
        vim.notify("Template has no .org file", vim.log.levels.ERROR)
        return nil
    end

    local cwd = vim.fn.getcwd()
    
    -- Якщо запуск з конфігів — тихо міняємо директорію на домашню
    if cwd:find(".config", 1, true) or cwd:find("nvim", 1, true) then
        cwd = vim.env.HOME
    end

    local filename = string.format(
        "%s_%s.org",
        tpl.id,
        os.date("%Y%m%d_%H%M%S")
    )

    local dst = cwd .. "/" .. filename

    -- Читаємо оригінальний файл шаблону
    local ok, content = pcall(vim.fn.readfile, tpl.org)
    if not ok then
        vim.notify("Failed to read template: " .. tpl.org, vim.log.levels.ERROR)
        return nil
    end

    -- Автоматичний збір полів з оригіналу шаблону
    local required_fields = {}
    for _, line in ipairs(content) do
        local field = line:match("^(#%+[A-Z0-9_]+):")
        if field then
            table.insert(required_fields, field)
        end
    end

    -- Якщо поля є, пишемо їх у технічний рядок першим рядком файлу
    if #required_fields > 0 then
        local tech_line = "#+DOC53_REQUIRED: " .. table.concat(required_fields, ",")
        table.insert(content, 1, tech_line)
    end
    
    -- Додаємо шлях до OTT шаблону
    if tpl.ott then
        local ott_line = string.format("#+ODT_STYLES_FILE: %s", tpl.ott)
        table.insert(content, 1, ott_line)
    end
    
    vim.fn.writefile(content, dst)
    
    return dst

end

return M
