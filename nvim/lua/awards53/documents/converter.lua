local M = {}
local context = require("awards53.documents.context")
local rnokpp_util = require("awards53.rnokpp")

-- Шлях до Python-обробника (поруч із converter.lua)
local script_path = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h") .. "/doc53_processor.py"

-- Запуск пакету завдань через Python-UNO
local function run_uno_tasks(tasks)
    local payload = vim.fn.json_encode({ tasks = tasks })
    local obj = vim.system({ "python3", script_path, payload }, { text = true }):wait()

    if obj.code ~= 0 then
        local err_msg = vim.trim(obj.stderr or "Невідома помилка обробки UNO")
        vim.notify("Помилка UNO:\n" .. err_msg, vim.log.levels.ERROR)
        return false
    end
    return true
end

-- 1. Зчитування метаданих з .org файлу
local function read_org_metadata(filepath)
    local metadata = { fields = {} }
    local f = io.open(filepath, "r")
    if not f then return nil end

    local current_key = nil
    local current_val_lines = {}

    local function save_current_field()
        if not current_key then return end

        local full_text = table.concat(current_val_lines, "\n")
        -- Зачищаємо зайві пробіли та переноси на початку і в кінці
        full_text = full_text:gsub("^%s+", ""):gsub("%s+$", "")

        if current_key == "ODT_STYLES_FILE" then
            local raw_odt = full_text:gsub('"', ''):gsub("'", "")
            metadata.odt = vim.fn.expand(raw_odt)
        elseif current_key ~= "DOC53_REQUIRED" then
            metadata.fields[current_key] = full_text
        end
    end

    for line in f:lines() do
        local key, val = line:match("^#%+([A-Z0-9_]+):%s*(.*)")

        if key then
            -- Зберігаємо попередньо накопичене поле
            save_current_field()

            current_key = key
            current_val_lines = { val or "" }
        elseif current_key then
            -- Додаємо наступні рядки до поточного ключа
            table.insert(current_val_lines, line)
        end
    end

    -- Зберігаємо останнє поле файлу
    save_current_field()

    f:close()
    return metadata
end

local function metadata_from_template(tpl)
    if not tpl then return nil end
    if type(tpl) == "string" then
        return { odt = vim.fn.expand(tpl), fields = {} }
    end
    if not tpl.org and tpl.odt then
        return { odt = vim.fn.expand(tpl.odt), fields = {} }
    end
    if not tpl.org then return nil end

    local meta = read_org_metadata(tpl.org) or { fields = {} }
    if tpl.odt then
        meta.odt = vim.fn.expand(tpl.odt)
    end
    return meta
end

local function get_metadata(opts, current_file)
    if opts.metadata then
        return opts.metadata
    end

    -- Перевіряємо opts.odt_path або opts.template
    if opts.odt_path then
        return { odt = vim.fn.expand(opts.odt_path), fields = opts.fields or {} }
    end

    if opts.template then
        return metadata_from_template(opts.template)
    end

    if current_file == "" then
        vim.notify("Помилка: Відкрийте збережений .org файл!", vim.log.levels.ERROR)
        return nil
    end

    return read_org_metadata(current_file)
end

local function parse_posada_field(posada_text)
    if not posada_text or posada_text == "" then return nil, nil, nil end

    local rnokpp = posada_text:match("(%d%d%d%d%d%d%d%d%d%d)")
    if not rnokpp or not rnokpp_util.is_valid(rnokpp) then return nil, nil, nil end

    local birth_date = rnokpp_util.get_birth_date_formatted(rnokpp)
    
    -- ВИПРАВЛЕНО: [%s%S] дозволяє захоплювати спецсимволи і переноси рядків (\n)
    local raw_rank = posada_text:match("України%s*,?%s*([%s%S].-)%s*" .. rnokpp)

    local rank = nil
    if raw_rank then
        rank = raw_rank:gsub("[%c\r\n]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub(",$", ""):lower()
    end

    local cleaned_posada = posada_text:gsub("(України)%s*,?.*$", "%1")
    return rank, birth_date, cleaned_posada
end

local function sanitize_to_uppercase_pib(str)
    if not str then return "БЕЗ_ІМЕНІ" end
    if type(str) == "table" then str = table.concat(str, " ") end

    str = tostring(str):gsub("\n", " ")
    str = vim.fn.toupper(str)
    str = str:gsub("[%/%\\%:%*%?%\"%<%>%|]", "")
    str = vim.trim(str)
    return (str ~= "") and str:gsub("%s+", "_") or "БЕЗ_ІМЕНІ"
end

-- Допоміжна функція безпечного з'єднання шляхів
local function join_path(dir, filename)
    return (dir:gsub("/+$", "") .. "/" .. filename)
end

-- =========================================================================
-- ЕКСПОРТОВАНІ ФУНКЦІЇ
-- =========================================================================

-- Створення зведеного документа (Подання з таблицею) або одиночного документу
function M.compile_to_odt(opts)
    opts = opts or {}
    local current_file = opts.org_file or vim.api.nvim_buf_get_name(0)

    -- Отримуємо метадані
    local meta = get_metadata(opts, current_file)

    if not meta or not meta.odt or meta.odt == "" then
        vim.notify("Помилка: Не знайдено шлях до шаблону .odt у метаданих!", vim.log.levels.ERROR)
        return
    end

    local odt_path = meta.odt
    if vim.fn.filereadable(odt_path) == 0 then
        vim.notify("Файл шаблону .odt не знайдено за шляхом: " .. odt_path, vim.log.levels.ERROR)
        return
    end

    local output_filename = opts.output_name or (vim.fn.fnamemodify(current_file, ":t:r") .. ".odt")
    local out_dir = opts.output_dir or vim.fn.fnamemodify(current_file, ":p:h")
    local final_odt_path = join_path(out_dir, output_filename)

    local awards_data = opts.awards_data or context.awards_data()

    -- Формуємо масив для заповнення таблиці
    local table_rows = {}
    if awards_data and awards_data.records then
        for _, rec in ipairs(awards_data.records) do
            local row = { "" } 
            local col_idx = 1

            while true do
                local val = rec[col_idx] or rec[tostring(col_idx)]
                if not val then break end

                if type(val) == "table" then 
                    val = table.concat(val, " ") 
                end

                table.insert(row, tostring(val))
                col_idx = col_idx + 1
            end

            table.insert(table_rows, row)
        end
    end   

    local task = {
        template = odt_path,
        output = final_odt_path,
        fields = meta.fields or {},
        table_data = table_rows
    }

    if run_uno_tasks({ task }) then
        vim.notify("Згенеровано зведений ODT: " .. output_filename, vim.log.levels.INFO)
    end
end

-- Генерація поодиноких нагородних листів
function M.generate_award_sheets(opts)
    opts = opts or {}
    local odt_path = opts.odt_path
    local awards_data = opts.awards_data
    local output_dir = opts.output_dir or vim.fn.getcwd()
    local created_files = {}

    if not awards_data or not awards_data.records or #awards_data.records == 0 then
        return created_files
    end

    local tasks = {}

    for i, record in ipairs(awards_data.records) do
        local rec_1 = record["1"] or record[1]
        local rec_3 = record["3"] or record[3]
        local rec_4 = record["4"] or record[4]

        local raw_pib = rec_1 or string.format("КАРТКА_%d", i)
        local upper_pib = sanitize_to_uppercase_pib(raw_pib)
        local output_filename = string.format("%s_orden_sheet.odt", upper_pib)
        local final_odt_path = join_path(output_dir, output_filename)

        local function get_field_text(field_val)
            if not field_val then return "" end
            if type(field_val) == "table" then return table.concat(field_val, "\n") end
            return tostring(field_val)
        end

        local raw_posada = get_field_text(rec_3)
        local parsed_rank, parsed_birth_date, cleaned_posada = parse_posada_field(raw_posada)
        local raw_char = get_field_text(rec_4)

        local award_name = raw_char:match("нагородження%s+(.+)")
        if award_name then award_name = vim.trim(award_name):gsub("%.$", "") end

        table.insert(tasks, {
            template = odt_path,
            output = final_odt_path,
            fields = {
                FIELD1 = get_field_text(rec_1),
                FIELD2 = cleaned_posada or "",
                FIELD3 = parsed_rank or "",
                FIELD4 = parsed_birth_date or "",
                FIELD5 = raw_char or "",
                FIELD6 = award_name or "",
            }
        })

        table.insert(created_files, output_filename)
    end

    if run_uno_tasks(tasks) then
        vim.notify("Успішно згенеровано документів: " .. #created_files, vim.log.levels.INFO)
    end

    return created_files
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

return M
