local M = {}

function M.create_document(tpl)
    if not tpl or not tpl.org then
        vim.notify("Шаблон не містить .org файлу", vim.log.levels.ERROR)
        return nil
    end

    local cfg = require("awards53").config or {}
    local cwd = vim.fn.getcwd()

    -- 1. Если в конфиге явно задан output_dir — используем его
    if cfg.output_dir and cfg.output_dir ~= "" then
        cwd = vim.fn.expand(cfg.output_dir)
    else
        -- 2. Безопасная проверка: меняем на HOME ТОЛЬКО если cwd СТРОГО совпадает 
        -- с директорией конфигурации Neovim (stdpath("config"))
        local nvim_config_dir = vim.fn.stdpath("config")
        if cwd == nvim_config_dir or cwd:sub(1, #nvim_config_dir + 1) == nvim_config_dir .. "/" then
            cwd = vim.env.HOME
        end
    end

    -- 3. Безопасная очистка tpl.id от слэшей, пробелов, точки с запятой и т.д.
    local safe_id = tostring(tpl.id or "doc"):gsub("[^%w%-_]", "_")

    local filename = string.format(
        "%s_%s.org",
        safe_id,
        os.date("%Y%m%d_%H%M%S")
    )

    -- Формируем корректный шлях
    local dst = vim.fs.normalize(cwd .. "/" .. filename)

    -- Читаем оригинальный файл шаблону
    local ok, content = pcall(vim.fn.readfile, tpl.org)
    if not ok then
        vim.notify("Не вдалося прочитати шаблон: " .. tpl.org, vim.log.levels.ERROR)
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

    -- Додаємо шлях до шаблону
    if tpl.odt then
        local odt_line = string.format("#+ODT_STYLES_FILE: %s", tpl.odt)
        table.insert(content, 1, odt_line)
    end

    -- 4. Запис файлу та перевірка результату
    local write_res = vim.fn.writefile(content, dst)
    if write_res ~= 0 then
        vim.notify("⛔ Не вдалося зберегти файл: " .. dst .. "\nПеревірте права доступу або існування директорії.", vim.log.levels.ERROR)
        return nil
    end

    return dst
end

return M
