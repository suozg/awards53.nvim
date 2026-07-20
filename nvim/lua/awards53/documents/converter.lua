local M = {}
local context = require("awards53.documents.context")
local inflect = require("awards53.inflect")

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


-- Екранування спецсимволів для XML
local function esc_xml(s)
    if not s then return "" end
    s = tostring(s)
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    s = s:gsub('"', "&quot;")
    s = s:gsub("'", "&apos;")
    
    -- 1. Замінюємо \n на системний перенос рядка LibreOffice
    s = s:gsub("\\n", "<text:line-break/>")
    
    -- 2. замінюємо \t на тег табуляції ODF
    s = s:gsub("\\t", "<text:tab/>")
    
    return s
end

-- ГЕНЕРАТОР РЯДКІВ З АВТОНУМЕРАЦІЄЮ
local function generate_odt_xml_rows(data, include_headers, use_autonum)
    -- Якщо передали nil або порожню таблицю без заголовків
    if not data or not data.headers then
        return ""
    end

    local out = {}
    
    -- 1. Додаємо заголовки (якщо створюється а не додається таблиця)
    if include_headers and data.headers then
        table.insert(out, '<table:table-row>')
        if use_autonum then
            table.insert(out, '<table:table-cell office:value-type="string"><text:p>№ з/п</text:p></table:table-cell>')
        end
        for _, h in ipairs(data.headers) do
            table.insert(out, '<table:table-cell office:value-type="string"><text:p>' .. esc_xml(h) .. '</text:p></table:table-cell>')
        end
        table.insert(out, '</table:table-row>')
    end

    -- 2. Заповнення рядків даними
    for i, rec in ipairs(data.records) do
        table.insert(out, '<table:table-row>')
        
        if use_autonum then
            table.insert(out, '<table:table-cell office:value-type="string">')
            table.insert(out, '<text:p>' .. tostring(i) .. '</text:p>')
            table.insert(out, '</table:table-cell>')
        end

        -- Заповнюємо решту стовпчиків
        for _, h in ipairs(data.headers) do
            table.insert(out, '<table:table-cell office:value-type="string">')
            
            local value = rec[h] or ""
            if type(value) == "table" then
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

    return table.concat(out, "")
end


local function update_content_xml(content_xml_path, meta, awards_data)
    local f = io.open(content_xml_path, "r")
    if not f then
        return false
    end

    local xml = f:read("*a")
    f:close()

    -- 1. Заміна текстових полів (працює завжди для листів)
    for key, value in pairs(meta.fields) do
        xml = xml:gsub(
            "DOCFIELD_" .. key,
            esc_xml(value)
        )
    end

    -- 2. ОБРОБКА ТАБЛИЦІ (Тільки якщо маркер дійсно є в шаблоні!)
    local has_table_marker = xml:find("DOCFIELD_TABLE")

    if has_table_marker then
        -- Визначаємо, чи потрібна автонумерація
        local use_autonum = false
        if awards_data and awards_data.headers then
            local pre_marker_xml = xml:match("^(.-)</table:table>%s*<text:p[^>]*>%s*DOCFIELD_TABLE")
            if not pre_marker_xml then
                pre_marker_xml = xml:match("^(.-)DOCFIELD_TABLE")
            end
            
            if pre_marker_xml then
                local table_content = pre_marker_xml:match(".*<table:table%s[^>]*>(.-)$")
                if table_content then
                    local col_count = 0
                    for _ in table_content:gmatch("<table:table%-column") do
                        col_count = col_count + 1
                    end
                    
                    if col_count > #awards_data.headers then
                        use_autonum = true
                    end
                end
            end
        end

        -- Генеруємо XML-рядки таблиці
        local rows_xml = ""
        if awards_data and awards_data.headers and #awards_data.headers > 0 then
            rows_xml = generate_odt_xml_rows(awards_data, false, use_autonum)
        else
            -- показуємо помилку, бо користувач вибрав табличний шаблон, але забув підключити базу
            rows_xml = [[<table:table-row><table:table-cell><text:p>[Помилка: Дані для таблиці Awards53 не знайдено]</text:p></table:table-cell></table:table-row>]]
        end

        -- Вставляємо рядки в таблицю шаблону
        local row_with_marker_pattern = "<table:table%-row[^>]*>.-DOCFIELD_TABLE.-</table:table%-row>"

        if xml:find(row_with_marker_pattern) then
            xml = xml:gsub(row_with_marker_pattern, rows_xml)
        else
            -- Якщо маркер стоїть відразу після таблиці
            local pattern = "</table:table>%s*<text:p[^>]*>%s*DOCFIELD_TABLE%s*</text:p>"
            if xml:find(pattern) then
                xml = xml:gsub(pattern, rows_xml .. "</table:table>")
            else
                -- Fallback (створюємо нову таблицю, тільки якщо дані реально є)
                if awards_data and awards_data.headers and #awards_data.headers > 0 then
                    local fallback_table = '<table:table table:name="AwardsTable">'
                    if use_autonum then
                        fallback_table = fallback_table .. '<table:table-column/>'
                    end
                    for _ = 1, #awards_data.headers do
                        fallback_table = fallback_table .. '<table:table-column/>'
                    end
                    fallback_table = fallback_table .. generate_odt_xml_rows(awards_data, true, use_autonum) .. '</table:table>'
                    
                    xml = xml:gsub("DOCFIELD_TABLE", fallback_table)
                end
            end
        end
    end

    -- 3. Записуємо готовий результат
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

-- функция создания параллельного файла (1 поле ПІБ)
function M.create_parallel_org(awards_data, output_dir, org_filename)
    if not awards_data or not awards_data.headers or #awards_data.headers == 0 then
        return
    end

    local first_field_key = awards_data.headers[1]
    local total_records = #awards_data.records
    local list_lines = {}

    -- 1. Формуємо нумерований список із правильними знаками пунктуації та переносами
    for i, record in ipairs(awards_data.records) do
        local raw_value = record[first_field_key] or ""
        local original_text = ""

        if type(raw_value) == "table" then
            original_text = table.concat(raw_value, " ")
        else
            original_text = tostring(raw_value)
        end

        -- Відмінюємо ПІБ за допомогою твого модуля
        local modified_value = inflect.to_accusative(original_text)
        
        -- Визначаємо знак в кінці рядка: якщо останній — крапка, якщо ні — крапка з комою
        local separator = (i == total_records) and "." or ";"
        
        -- Формуємо рядок списку. Додаємо \n в кінці кожного рядка (крім останнього),
        -- щоб LibreOffice переносив їх на новий рядок всередині одного абзацу.
        local line_suffix = (i == total_records) and "" or "\\n"
        
        table.insert(list_lines, string.format("%d. %s%s%s", i, modified_value, separator, line_suffix))
    end

    -- Збираємо весь список в один суцільний рядок для поля #+BODY
    local body_content = table.concat(list_lines, " ")

    -- 2. Створюємо вміст за твоїм шаблоном, вставляючи список у середнє поле (#+BODY)
    local org_template = {
        "#+ODT_STYLES_FILE: /home/alex320388/.config/nvim/templates/templates53/documents/letter/letter.ott",
        "#+DOC53_REQUIRED: #+HEAD,#+BODY,#+FOOTER",
        "#+HEAD: АДРЕСАТ",
        "#+BODY: " .. body_content,
        "#+FOOTER: Командир військової частини А0536"
    }

    -- 3. Записуємо готовий файл поруч
    local intermediate_org = output_dir .. "/" .. org_filename
    
    local f = io.open(intermediate_org, "w")
    if f then
        f:write(table.concat(org_template, "\n"))
        f:close()

        -- відкриваємо файл в vim
        vim.cmd("edit " .. vim.fn.fnameescape(intermediate_org))
    end

end

return M
