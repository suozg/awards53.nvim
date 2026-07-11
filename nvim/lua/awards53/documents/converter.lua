local M = {}

-- Функція для парсингу метаданих з .org файлу
local function get_metadata(filepath)
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

function M.compile_to_odt()
    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file == "" or vim.fn.fnamemodify(current_file, ":e") ~= "org" then
        vim.notify("Помилка: Відкрийте збережений .org file!", vim.log.levels.ERROR)
        return
    end

    vim.cmd("write")

    local meta = get_metadata(current_file)
    if not meta or not meta.ott then
        vim.notify("Помилка: Не знайдено шлях до .ott у файлі!", vim.log.levels.ERROR)
        return
    end

    if vim.fn.filereadable(meta.ott) == 0 then
        vim.notify("Помилка: Файл шаблону .ott не знайдено за шляхом: " .. meta.ott, vim.log.levels.ERROR)
        return
    end

    local final_odt = vim.fn.fnamemodify(current_file, ":r") .. ".odt"
    local tmp_dir = vim.fn.tempname() .. "_dir"
    vim.fn.mkdir(tmp_dir, "p")

    if vim.fn.executable("7z") == 0 then
        vim.notify("Помилка: Утиліту '7z' не знайдено в системі!", vim.log.levels.ERROR)
        vim.fn.delete(tmp_dir, "rf")
        return
    end

    -- 1. Розпаковуємо шаблон
    local unzip_cmd = string.format("7z x %s -o%s -y > /dev/null", vim.fn.shellescape(meta.ott), vim.fn.shellescape(tmp_dir))
    vim.fn.system(unzip_cmd)

    -- 2. Обробляємо content.xml
    local content_xml_path = tmp_dir .. "/content.xml"
    local f_xml = io.open(content_xml_path, "r")
    if not f_xml then
        vim.notify("Помилка: Не вдалося розпакувати шаблон за допомогою 7z!", vim.log.levels.ERROR)
        vim.fn.delete(tmp_dir, "rf")
        return
    end
    local xml_content = f_xml:read("*a")
    f_xml:close()

    -- ПРЯМА ЗАМІНА БЕЗ ЕКРАНУВАННЯ
    for key, value in pairs(meta.fields) do
        -- Збираємо чисте текстове ім'я плейсхолдера, наприклад: DOCFIELD_HEAD
        local placeholder = "DOCFIELD_" .. key
        
        -- Робимо пряму заміну в тексті XML
        xml_content = xml_content:gsub(placeholder, value)
    end

    local f_xml_write = io.open(content_xml_path, "w")
    if f_xml_write then
        f_xml_write:write(xml_content)
        f_xml_write:close()
    end

    -- 3. Збираємо .odt назад
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

    -- 4. Переносимо готовий архів
    if vim.fn.filereadable(tmp_odt_path) == 1 then
        if vim.fn.filereadable(final_odt) == 1 then
            vim.fn.delete(final_odt)
        end
        vim.fn.rename(tmp_odt_path, final_odt)
        vim.notify("Документ ODT успішно створено!", vim.log.levels.INFO)
    else
        vim.notify("Помилка: Файл не з'явився після роботи 7z!", vim.log.levels.ERROR)
    end

    vim.fn.delete(tmp_dir, "rf")
end

return M
