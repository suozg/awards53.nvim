local M = {}
local context = require("awards53.documents.context")

-- Функція для парсингу метаданих з .org файлу
local function read_org_metadata(filepath)
    local metadata = { fields = {} }
    local f = io.open(filepath, "r")
    if not f then return nil end

    for line in f:lines() do
        -- Шукаємо шлях до OTT шаблону
        local ott = line:match("^#%+ODT_STYLES_FILE:%s*(.+)")
        if ott then
            metadata.ott = ott:gsub('"', ''):gsub("'", ""):match("^%s*(.-)%s*$")
        end

        -- Шукаємо значення полів
        local key, val = line:match("^#%+([A-Z0-9_]+):%s*(.+)")
        if key and key ~= "ODT_STYLES_FILE" and key ~= "DOC53_REQUIRED" then
            metadata.fields[key] = val:match("^%s*(.-)%s*$")
        end
    end
    f:close()
    return metadata
end

local function metadata_from_template(tpl)
    if not tpl or not tpl.org then
        return nil
    end

    local meta = read_org_metadata(tpl.org)
    if not meta then
        return nil
    end

    if tpl.ott then
        meta.ott = tpl.ott
    end

    return meta
end

-- Екранування спецсимволів для XML, щоб не ламалася розмітка
local function esc_xml(s)
    if not s then return "" end
    s = tostring(s)
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    s = s:gsub('"', "&quot;")
    s = s:gsub("'", "&apos;")
    return s
end

-- ГЕНЕРАТОР ПРАВИЛЬНОЇ ТАБЛИЦІ ДЛЯ LIBREOFFICE
local function generate_odt_xml_table(data)
    local out = {}
    
    -- Початок ODF-таблиці
    table.insert(out, '<table:table table:name="AwardsTable">')
    
    -- Оголошуємо специфікацію колонок відповідно до заголовків
    for _ = 1, #data.headers do
        table.insert(out, '<table:table-column/>')
    end

    -- 1. Генерація рядка заголовків
    table.insert(out, '<table:table-row>')
    for _, h in ipairs(data.headers) do
        table.insert(out, '<table:table-cell office:value-type="string">')
        table.insert(out, '<text:p>' .. esc_xml(h) .. '</text:p>')
        table.insert(out, '</table:table-cell>')
    end
    table.insert(out, '</table:table-row>')

    -- 2. Заповнення рядків даними карток військовослужбовців
    for _, rec in ipairs(data.records) do
        table.insert(out, '<table:table-row>')
        for _, h in ipairs(data.headers) do
            table.insert(out, '<table:table-cell office:value-type="string">')
            
            local value = rec[h] or {}
            if type(value) == "table" then
                -- Якщо всередині однієї комірки є кілька рядків, кожен обгортаємо в <text:p>
                for _, line in ipairs(value) do
                    if vim.trim(line) ~= "" then
                        table.insert(out, '<text:p>' .. esc_xml(line) .. '</text:p>')
                    end
                end
            else
                table.insert(out, '<text:p>' .. esc_xml(value) .. '</text:p>')
            end
            
            table.insert(out, '</table:table-cell>')
        end
        table.insert(out, '</table:table-row>')
    end

    table.insert(out, '</table:table>')
    return table.concat(out, "")
end


local function update_content_xml(content_xml_path, meta, awards_data)

    local f = io.open(content_xml_path, "r")
    if not f then
        return false
    end

    local xml = f:read("*a")
    f:close()

    -- текстовые поля
    for key, value in pairs(meta.fields) do
        xml = xml:gsub(
            "DOCFIELD_" .. key,
            esc_xml(value)
        )
    end

    -- таблица
    local table_xml

    if awards_data then
        table_xml = generate_odt_xml_table(awards_data)
    else
        table_xml =
[[<table:table table:name="Errors"><table:table-column/><table:table-row><table:table-cell><text:p>[Помилка: Базу даних Awards53 не знайдено]</text:p></table:table-cell></table:table-row></table:table>]]
    end

    local pattern = "<text:p[^>]*>DOCFIELD_TABLE</text:p>"

    if xml:find(pattern) then
        xml = xml:gsub(pattern, table_xml)
    else
        xml = xml:gsub("DOCFIELD_TABLE", table_xml)
    end

    f = io.open(content_xml_path, "w")
    if not f then
        return false
    end

    f:write(xml)
    f:close()

    return true
end


local function get_metadata(opts, current_file)

    if opts.metadata then
        return opts.metadata
    end

    if opts.template then
        return metadata_from_template(opts.template)
    end

    if current_file == "" then
        vim.notify("Помилка: Відкрийте збережений .org файл!", vim.log.levels.ERROR)
        return nil
    end

    vim.cmd("write")
    return read_org_metadata(current_file)

end

function M.compile_to_odt(opts)
    opts = opts or {}

    local current_file = opts.org_file or vim.api.nvim_buf_get_name(0)

    local meta = get_metadata(opts, current_file)

    if not meta then
        vim.notify("Не вдалося отримати метадані документа.", vim.log.levels.ERROR)
        return
    end

    if not meta or not meta.ott then
        vim.notify("Помилка: Не знайдено шлях до шаблону .ott у метаданих!", vim.log.levels.ERROR)
        return
    end

    local ott_path = meta.ott
    if vim.fn.filereadable(ott_path) == 0 then
        vim.notify("Файл шаблону .ott не знайдено за шляхом: " .. ott_path, vim.log.levels.ERROR)
        return
    end

    -- 1. Створюємо тимчасову робочу директорію
    local tmp_dir = vim.fn.tempname()
    vim.fn.mkdir(tmp_dir, "p")

    -- 2. Розпаковуємо .ott за допомогою 7z
    local unzip_cmd = string.format("7z x %s -o%s > /dev/null", vim.fn.shellescape(ott_path), vim.fn.shellescape(tmp_dir))
    vim.fn.system(unzip_cmd)

    local content_xml_path = tmp_dir .. "/content.xml"

    local awards_data = opts.awards_data or context.awards_data()

    if not update_content_xml(content_xml_path, meta, awards_data) then
        vim.notify(
            "Не вдалося оновити content.xml",
            vim.log.levels.ERROR
        )
        vim.fn.delete(tmp_dir, "rf")
        return
    end

    -- 3. Пакуємо змінений контент назад у формат .odt
    local save_cwd = vim.fn.getcwd()
    vim.cmd("lcd " .. vim.fn.fnameescape(tmp_dir))

    local shell_cmd = "7z a -tzip -mx=9 output.odt * > /dev/null"
    vim.fn.system(shell_cmd)
    local zip_exit_code = vim.v.shell_error

    vim.cmd("lcd " .. vim.fn.fnameescape(save_cwd))

    if zip_exit_code ~= 0 then
        vim.notify("Помилка 7z при збірці архіву! Код: " .. zip_exit_code, vim.log.levels.ERROR)
        vim.fn.delete(tmp_dir, "rf")
        return
    end

    local tmp_odt_path = tmp_dir .. "/output.odt"

    -- 4. Зберігаємо фінальний документ у поточній директорії
    local output_filename

    if opts.output_name then
        output_filename = opts.output_name
    else
        output_filename = vim.fn.fnamemodify(current_file, ":t:r") .. ".odt"
    end

    local out_dir

    if opts.output_dir then
        out_dir = opts.output_dir
    else
        out_dir = vim.fn.fnamemodify(current_file, ":p:h")
    end

    local final_odt_path = out_dir .. "/" .. output_filename

    local move_ok = vim.fn.rename(tmp_odt_path, final_odt_path)
    
    -- Видаляємо сліди у тимчасовій папці
    vim.fn.delete(tmp_dir, "rf")

    if move_ok == 0 then
        vim.notify("Документ успішно створено: " .. output_filename, vim.log.levels.INFO)
    else
        vim.notify("Не вдалося зберегти фінальний .odt файл!", vim.log.levels.ERROR)
    end
end

function M.convert_current()
    local context = require("awards53.documents.context")

    local mode = context.mode()

    if mode == "org" then
        return M.compile_to_odt({
            org_file = vim.api.nvim_buf_get_name(0),
        })
    end

    if mode == "awards" then
        vim.notify(
            "Для Awards53 потрібно вибрати шаблон через :Documents53",
            vim.log.levels.INFO
        )
        return
    end

    vim.notify(
        "Поточний буфер не можна конвертувати.",
        vim.log.levels.ERROR
    )
end

return M
