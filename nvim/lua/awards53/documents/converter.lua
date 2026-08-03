local M = {}
local context = require("awards53.documents.context")
local inflect = require("awards53.inflect")

-- Функція для парсингу метаданих з .org файлу
local function read_org_metadata(filepath)
    local metadata = { fields = {} }
    local f = io.open(filepath, "r")
    if not f then return nil end

    for line in f:lines() do
        local ott = line:match("^#%+ODT_STYLES_FILE:%s*(.+)")
        if ott then
            metadata.ott = ott:gsub('"', ''):gsub("'", ""):match("^%s*(.-)%s*$")
        end

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
    
    s = s:gsub("\r\n", "\n")
    s = s:gsub("\r", "\n")
    s = s:gsub("\n", "<text:line-break/>")
    s = s:gsub("\t", "<text:tab/>")
    
    return s
end

-- =========================================================================
-- ХЕЛПЕРИ ДЛЯ ТАБЛИЦЬ (Оптимізація та спрощення)
-- =========================================================================

-- Перевірка наявності маркерів таблиці у XML
local function has_table_marker(xml)
    return xml:find("DOCFIELD_TABLE") ~= nil
end

-- Визначення кількості колонок у таблиці шаблону
local function get_template_column_count(xml)
    local pre_marker_xml = xml:match("^(.-)</table:table>%s*<text:p[^>]*>%s*DOCFIELD_TABLE")
        or xml:match("^(.-)DOCFIELD_TABLE")
    
    if not pre_marker_xml then return 0 end

    local table_content = pre_marker_xml:match(".*<table:table%s[^>]*>(.-)$")
    if not table_content then return 0 end

    local col_count = 0
    for _ in table_content:gmatch("<table:table%-column") do
        col_count = col_count + 1
    end
    return col_count
end

-- Генерація рядків ODT-таблиці
local function generate_odt_xml_rows(awards_data, include_headers, use_autonum)
    if not awards_data or not awards_data.headers then
        return ""
    end

    local out = {}
    
    if include_headers and awards_data.headers then
        table.insert(out, '<table:table-row>')
        if use_autonum then
            table.insert(out, '<table:table-cell office:value-type="string"><text:p>№ з/п</text:p></table:table-cell>')
        end
        for _, h in ipairs(awards_data.headers) do
            table.insert(out, '<table:table-cell office:value-type="string"><text:p>' .. esc_xml(h) .. '</text:p></table:table-cell>')
        end
        table.insert(out, '</table:table-row>')
    end

    for i, rec in ipairs(awards_data.records) do
        table.insert(out, '<table:table-row>')
        
        if use_autonum then
            table.insert(out, '<table:table-cell office:value-type="string">')
            table.insert(out, '<text:p>' .. tostring(i) .. '</text:p>')
            table.insert(out, '</table:table-cell>')
        end

        for _, h in ipairs(awards_data.headers) do
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

-- Заміна маркерів таблиці за допомогою чистих хелперів
local function process_table_marker(xml, awards_data)
    if not has_table_marker(xml) then return xml end

    local use_autonum = false
    if awards_data and awards_data.headers then
        local col_count = get_template_column_count(xml)
        if col_count > #awards_data.headers then
            use_autonum = true
        end
    end

    local rows_xml = ""
    if awards_data and awards_data.headers and #awards_data.headers > 0 then
        rows_xml = generate_odt_xml_rows(awards_data, false, use_autonum)
    else
        rows_xml = [[<table:table-row><table:table-cell><text:p>[Помилка: Дані для таблиці Awards53 не знайдено]</text:p></table:table-cell></table:table-row>]]
    end

    local row_with_marker_pattern = "<table:table%-row[^>]*>.-DOCFIELD_TABLE.-</table:table%-row>"
    if xml:find(row_with_marker_pattern) then
        return xml:gsub(row_with_marker_pattern, rows_xml)
    end

    local pattern = "</table:table>%s*<text:p[^>]*>%s*DOCFIELD_TABLE%s*</text:p>"
    if xml:find(pattern) then
        return xml:gsub(pattern, rows_xml .. "</table:table>")
    end

    if awards_data and awards_data.headers and #awards_data.headers > 0 then
        local fallback_table = '<table:table table:name="AwardsTable">'
        if use_autonum then
            fallback_table = fallback_table .. '<table:table-column/>'
        end
        for _ = 1, #awards_data.headers do
            fallback_table = fallback_table .. '<table:table-column/>'
        end
        fallback_table = fallback_table .. generate_odt_xml_rows(awards_data, true, use_autonum) .. '</table:table>'
        
        return xml:gsub("DOCFIELD_TABLE", fallback_table)
    end

    return xml
end

-- =========================================================================

local function update_content_xml(content_xml_path, meta, awards_data)
    local f = io.open(content_xml_path, "r")
    if not f then
        return false
    end

    local xml = f:read("*a")
    f:close()

    for key, value in pairs(meta.fields) do
        xml = xml:gsub("DOCFIELD_" .. key, esc_xml(value))
    end

    xml = process_table_marker(xml, awards_data)

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

    if not meta or not meta.ott then
        vim.notify("Помилка: Не знайдено шлях до шаблону .ott у метаданих!", vim.log.levels.ERROR)
        return
    end

    local ott_path = meta.ott
    if vim.fn.filereadable(ott_path) == 0 then
        vim.notify("Файл шаблону .ott не знайдено за шляхом: " .. ott_path, vim.log.levels.ERROR)
        return
    end

    local tmp_dir = vim.fn.tempname()
    vim.fn.mkdir(tmp_dir, "p")

    local unzip_cmd = string.format("7z x %s -o%s > /dev/null", vim.fn.shellescape(ott_path), vim.fn.shellescape(tmp_dir))
    vim.fn.system(unzip_cmd)

    local content_xml_path = tmp_dir .. "/content.xml"
    local awards_data = opts.awards_data or context.awards_data()

    if not update_content_xml(content_xml_path, meta, awards_data) then
        vim.notify("Не вдалося оновити content.xml", vim.log.levels.ERROR)
        vim.fn.delete(tmp_dir, "rf")
        return
    end

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
    local output_filename = opts.output_name or (vim.fn.fnamemodify(current_file, ":t:r") .. ".odt")
    local out_dir = opts.output_dir or vim.fn.fnamemodify(current_file, ":p:h")
    local final_odt_path = out_dir .. "/" .. output_filename

    local move_ok = vim.fn.rename(tmp_odt_path, final_odt_path)
    vim.fn.delete(tmp_dir, "rf")

    if move_ok == 0 then
        vim.notify("Документ успішно створено: " .. output_filename, vim.log.levels.INFO)
    else
        vim.notify("Не вдалося зберегти фінальний .odt файл!", vim.log.levels.ERROR)
    end
end

function M.convert_current()
    local mode = context.mode()

    if mode == "org" then
        return M.compile_to_odt({
            org_file = vim.api.nvim_buf_get_name(0),
        })
    end

    if mode == "awards" then
        require("awards53.documents.init").open()
        return
    end

    vim.notify(
        "Поточний буфер не є документом Documents53 або базою Awards53.",
        vim.log.levels.ERROR
    )
end

function M.create_parallel_org(awards_data, output_dir, org_filename)
    if not awards_data or not awards_data.headers or #awards_data.headers == 0 then
        return
    end

    local first_field_key = awards_data.headers[1]
    local total_records = #awards_data.records
    local list_lines = {}

    for i, record in ipairs(awards_data.records) do
        local raw_value = record[first_field_key] or ""
        local original_text = type(raw_value) == "table" and table.concat(raw_value, " ") or tostring(raw_value)

        local modified_value = inflect.to_accusative(original_text)
        local separator = (i == total_records) and "." or ";"
        local line_suffix = (i == total_records) and "" or "\n"
        
        table.insert(list_lines, string.format("%d. %s%s%s", i, modified_value, separator, line_suffix))
    end

    local body_content = table.concat(list_lines, " ")

    local org_template = {
        "#+ODT_STYLES_FILE: " .. vim.fn.stdpath("config") .. "/templates/templates53/documents/letter/letter.ott",
        "#+DOC53_REQUIRED: #+HEAD,#+BODY,#+FOOTER",
        "#+HEAD: АДРЕСАТ",
        "#+BODY: " .. body_content,
        "#+FOOTER: Командир військової частини А0536"
    }

    local intermediate_org = output_dir .. "/" .. org_filename
    local f = io.open(intermediate_org, "w")
    if f then
        f:write(table.concat(org_template, "\n"))
        f:close()
        vim.cmd("edit " .. vim.fn.fnameescape(intermediate_org))
    end
end

local MONTHS_UA = {
    "січня", "лютого", "березня", "квітня", "травня", "червня",
    "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"
}

local function parse_rnokpp(rnokpp_str)
    if not rnokpp_str or #rnokpp_str ~= 10 then return nil end
    local days = tonumber(rnokpp_str:sub(1, 5))
    if not days then return nil end

    local base_time = os.time({year = 1899, month = 12, day = 31, hour = 12})
    local birth_time = base_time + (days * 86400)
    local t = os.date("*t", birth_time)

    if not t or not t.year or not t.month or not t.day then return nil end

    return string.format("%d %s %d року", t.day, MONTHS_UA[t.month] or "", t.year)
end

local function parse_posada_field(posada_text)
    if not posada_text or posada_text == "" then
        return nil, nil
    end

    local rnokpp = posada_text:match("(%d%d%d%d%d%d%d%d%d%d)")
    if not rnokpp then
        return nil, nil
    end

    local birth_date = parse_rnokpp(rnokpp)
    local raw_rank = posada_text:match("України%s*,?%s*(.-)%s*" .. rnokpp)

    local rank = nil
    if raw_rank then
        rank = raw_rank
            :gsub("[%c\r\n]+", " ")
            :gsub("%s+", " ")
            :gsub("^%s+", "")
            :gsub("%s+$", "")
            :gsub(",$", "")
            :lower()
    end
    
    local cleaned_posada = posada_text:gsub("(України)%s*,?.*$", "%1")
    return rank, birth_date, cleaned_posada
end

local function sanitize_to_uppercase_pib(str)
    if not str then return "БЕЗ_ІМЕНІ" end
    if type(str) == "table" then
        str = table.concat(str, " ")
    end

    str = tostring(str):gsub("\n", " ")
    str = vim.fn.toupper(str)
    str = str:gsub("[%/%\\%:%*%?%\"%<%>%|]", "")
    str = vim.trim(str)
    str = str:gsub("%s+", "_")

    return (str ~= "") and str or "БЕЗ_ІМЕНІ"
end

function M.generate_award_sheets(opts)
    opts = opts or {}
    local ott_path = opts.ott_path
    local awards_data = opts.awards_data
    local output_dir = opts.output_dir or vim.fn.getcwd()
    local created_files = {}

    if not awards_data or not awards_data.records or #awards_data.records == 0 then
        return created_files
    end

    local records = awards_data.records
    local tmp_dir = vim.fn.tempname()
    vim.fn.mkdir(tmp_dir, "p")

    local unzip_cmd = string.format("7z x %s -o%s > /dev/null", vim.fn.shellescape(ott_path), vim.fn.shellescape(tmp_dir))
    vim.fn.system(unzip_cmd)

    local content_xml_path = tmp_dir .. "/content.xml"
    local f = io.open(content_xml_path, "r")
    if not f then
        vim.fn.delete(tmp_dir, "rf")
        return created_files
    end

    local xml_template = f:read("*a")
    f:close()

    for i, record in ipairs(records) do
        local raw_pib = record["1"] or record[1] or string.format("КАРТКА_%d", i)
        local upper_pib = sanitize_to_uppercase_pib(raw_pib)
        local output_filename = string.format("%s_orden_sheet.odt", upper_pib)
        local single_tmp_dir = vim.fn.tempname()
        
        vim.fn.system(string.format("cp -r %s %s", vim.fn.shellescape(tmp_dir), vim.fn.shellescape(single_tmp_dir)))
        local single_xml = xml_template

        local function get_field_text(field_val)
            if not field_val then return "" end
            if type(field_val) == "table" then return table.concat(field_val, "\n") end
            return tostring(field_val)
        end

        local raw_posada = get_field_text(record["3"] or record[3])
        local parsed_rank, parsed_birth_date, cleaned_posada = parse_posada_field(raw_posada)
        local raw_char = get_field_text(record["4"] or record[4])

        local award_name = raw_char:match("нагородження%s+(.+)")
        if award_name then
            award_name = vim.trim(award_name):gsub("%.$", "")
        end

        local field_mapping = {
            ["1"] = get_field_text(record["1"] or record[1]),
            ["2"] = cleaned_posada,
            ["3"] = parsed_rank,
            ["4"] = parsed_birth_date,
            ["5"] = raw_char,
            ["6"] = award_name,
        }

        for num_str, raw_text in pairs(field_mapping) do
            single_xml = single_xml:gsub(
                "__FIELD" .. num_str .. "__",
                esc_xml(raw_text)
            )
        end

        local single_content_path = single_tmp_dir .. "/content.xml"
        local f_out = io.open(single_content_path, "w")
        if f_out then
            f_out:write(single_xml)
            f_out:close()
        end

        local save_cwd = vim.fn.getcwd()
        vim.cmd("lcd " .. vim.fn.fnameescape(single_tmp_dir))
        vim.fn.system("7z a -tzip -mx=9 output.odt * > /dev/null")
        vim.cmd("lcd " .. vim.fn.fnameescape(save_cwd))

        local final_odt_path = output_dir .. "/" .. output_filename
        vim.fn.rename(single_tmp_dir .. "/output.odt", final_odt_path)
        vim.fn.delete(single_tmp_dir, "rf")

        table.insert(created_files, output_filename)
    end

    vim.fn.delete(tmp_dir, "rf")
    return created_files
end

return M
