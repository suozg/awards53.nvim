-- search.lua
--
-- функції пошуку даних в файлах та базах даних
local M = {}
local utils = require("awards53.utils")
local uv = vim.uv or vim.loop

-- ==================== КОНФІГУРАЦІЯ ====================

local SEARCHDOCS_PATH = vim.fn.stdpath("config") .. "/bin/search.sh"
local SEARCH_DIR = vim.fn.expand("~/STATYSTYKA/shtat/")

local SEARCHSQL_PATH = vim.fn.stdpath("config") .. "/bin/sql_search.sh"
local DB_PATH = vim.fn.expand("~/awards/awards_v4e.db")

local cached_passwords = {
    gpg = nil,
    db = nil,
}

-- ==================== УПРАВЛІННЯ КЕШЕМ ПАРОЛІВ ====================

function M.clear_passwords()
    cached_passwords.gpg = nil
    cached_passwords.db = nil
    utils.info("🧹 Кеш паролів очищено")
end

-- ==================== ДОПОМІЖНІ ФУНКЦІЇ ====================

local function get_keyboard_layout_indicator()
    if vim.fn.executable("xkb-switch") ~= 1 then
        return "🗽US"
    end
    local obj = vim.system({ "xkb-switch", "-p" }, { text = true, timeout = 500 }):wait()
    if obj.code == 0 and obj.stdout then
        if vim.trim(obj.stdout) == "ua" then
            return "🌻UA"
        end
    end
    return "🗽US"
end

local function extract_default_rnokpp()
    local state = require("awards53.state")
    local record = state.current_record()
    if not record then return "" end

    local card_text = ""
    for _, field_val in pairs(record) do
        if type(field_val) == "table" then
            card_text = card_text .. " " .. table.concat(field_val, " ")
        elseif type(field_val) == "string" then
            card_text = card_text .. " " .. field_val
        end
    end

    local match = card_text:match("(%d%d%d%d%d%d%d%d%d%d)")
    return match or ""
end

-- Отримання актуального абсолютного шляху до файлу в поточному буфері
local function get_current_filepath()
    local state = require("awards53.state")
    local src_buf = state.get_source_buffer() or vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(src_buf)
    if name and name ~= "" then
        return vim.fn.fnamemodify(name, ":p")
    end
    return nil
end


-- ==================== ВЗАЄМОДІЯ З ГЛОБАЛЬНИМ КЕШЕМ (JSON) ====================

local function get_cache_file_path()
    return vim.fn.stdpath("state") .. "/awards53/bookmarks.json"
end

-- ---------------------------------------------------------------------------
-- Пошук записів, які більше не мають відповідних файлів.
-- Функція ТІЛЬКИ шукає, нічого не видаляє і нічого не повідомляє.
-- ---------------------------------------------------------------------------

local function find_missing_entries(root)
    if type(root) ~= "table" then
        return {}, {}
    end

    root.bookmarks = root.bookmarks or {}
    root.rnokpp_cache = root.rnokpp_cache or {}

    local missing_bookmarks = {}
    local missing_cache = {}

    -- Перевірка закладок
    for filepath, _ in pairs(root.bookmarks) do
        if vim.fn.filereadable(filepath) == 0 then
            table.insert(missing_bookmarks, filepath)
        end
    end

    -- Перевірка кешу РНОКПП
    for filepath, _ in pairs(root.rnokpp_cache) do
        if vim.fn.filereadable(filepath) == 0 then
            table.insert(missing_cache, filepath)
        end
    end

    return missing_bookmarks, missing_cache
end

-- ---------------------------------------------------------------------------
-- Видалення знайдених записів.
-- ---------------------------------------------------------------------------

local function remove_missing_entries(root, missing_bookmarks, missing_cache)
    root.bookmarks = root.bookmarks or {}
    root.rnokpp_cache = root.rnokpp_cache or {}

    for _, filepath in ipairs(missing_bookmarks) do
        root.bookmarks[filepath] = nil
    end

    for _, filepath in ipairs(missing_cache) do
        root.rnokpp_cache[filepath] = nil
    end

    return root
end

-- ---------------------------------------------------------------------------
-- Формування повідомлення про кількість очищених записів.
-- ---------------------------------------------------------------------------

local function missing_entries_message(missing_bookmarks, missing_cache)
    local removed_bm = #missing_bookmarks
    local removed_cache = #missing_cache

    return string.format(
        "🧹 Очищено %d закладок та %d кешів РНОКПП (файли не знайдено)",
        removed_bm,
        removed_cache
    )
end

-- ---------------------------------------------------------------------------
-- Читання глобального JSON-кешу.
--
-- Якщо знайдені записи для неіснуючих файлів:
--   1. показується повідомлення;
--   2. користувач підтверджує очищення;
--   3. тільки після підтвердження записи видаляються.
--
-- Якщо користувач відмовився — JSON залишається без змін.
-- ---------------------------------------------------------------------------

local function load_root_json()
    local file_path = get_cache_file_path()

    if vim.fn.filereadable(file_path) == 0 then
        return {
            bookmarks = {},
            rnokpp_cache = {},
        }
    end

    local lines = vim.fn.readfile(file_path)

    if not lines or #lines == 0 then
        return {
            bookmarks = {},
            rnokpp_cache = {},
        }
    end

    local ok, root = pcall(
        vim.json.decode,
        table.concat(lines, "\n")
    )

    if not ok or type(root) ~= "table" then
        return {
            bookmarks = {},
            rnokpp_cache = {},
        }
    end

    root.bookmarks = root.bookmarks or {}
    root.rnokpp_cache = root.rnokpp_cache or {}

    -- Спочатку тільки перевіряємо.
    local missing_bookmarks, missing_cache =
        find_missing_entries(root)

    if #missing_bookmarks == 0 and #missing_cache == 0 then
        return root
    end

    local removed_bm = #missing_bookmarks
    local removed_cache = #missing_cache

    local message = string.format(
        "У JSON знайдено записи для відсутніх файлів.\n\n" ..
        "Закладок: %d\n" ..
        "Кешів РНОКПП: %d\n\n" ..
        "Очистити ці записи?",
        removed_bm,
        removed_cache
    )

    local answer = vim.fn.confirm(
        message,
        "&Yes\n&No",
        1
    )

    if answer == 1 then
        root = remove_missing_entries(
            root,
            missing_bookmarks,
            missing_cache
        )

        -- Зберігаємо вже очищений root.
        -- save_root_json() повторно перевіряти його не буде.
        local json_str = vim.json.encode(root)
        local tmp = file_path .. ".tmp"

        vim.fn.mkdir(
            vim.fn.fnamemodify(file_path, ":h"),
            "p"
        )

        local write_ok = pcall(
            vim.fn.writefile,
            vim.split(json_str, "\n"),
            tmp
        )

        if write_ok then
            pcall(uv.fs_unlink, file_path)
            pcall(uv.fs_rename, tmp, file_path)
        end

        utils.info(string.format(
            "🧹 Очищено %d закладок та %d кешів РНОКПП",
            removed_bm,
            removed_cache
        ))
    end

    return root
end

-- ---------------------------------------------------------------------------
-- Запис глобального JSON-кешу.
--
-- При записі очищення виконується АВТОМАТИЧНО.
-- Підтвердження не запитується.
-- Після запису повідомляється тільки про фактично видалені записи.
-- ---------------------------------------------------------------------------

local function save_root_json(root)
    if type(root) ~= "table" then
        return
    end

    root.bookmarks = root.bookmarks or {}
    root.rnokpp_cache = root.rnokpp_cache or {}

    -- При записі перевіряємо кеш без підтвердження.
    local missing_bookmarks, missing_cache =
        find_missing_entries(root)

    local removed_bm = #missing_bookmarks
    local removed_cache = #missing_cache

    if removed_bm > 0 or removed_cache > 0 then
        root = remove_missing_entries(
            root,
            missing_bookmarks,
            missing_cache
        )
    end

    local file_path = get_cache_file_path()
    local dir = vim.fn.fnamemodify(file_path, ":h")

    vim.fn.mkdir(dir, "p")

    local json_str = vim.json.encode(root)
    local tmp = file_path .. ".tmp"

    local ok = pcall(
        vim.fn.writefile,
        vim.split(json_str, "\n"),
        tmp
    )

    if ok then
        pcall(uv.fs_unlink, file_path)
        pcall(uv.fs_rename, tmp, file_path)
    else
        return
    end

    -- При записі тільки повідомляємо про автоматичне очищення.
    if removed_bm > 0 or removed_cache > 0 then
        utils.info(string.format(
            "🧹 Під час запису очищено %d закладок та %d кешів РНОКПП (файли не знайдено)",
            removed_bm,
            removed_cache
        ))
    end
end

-- ---------------------------------------------------------------------------
-- Отримання кешу РНОКПП для конкретного файлу.
-- ---------------------------------------------------------------------------

local function load_rnokpp_cache_for_file(filepath)
    if not filepath then
        return {}
    end

    local root = load_root_json()

    return root.rnokpp_cache[filepath] or {}
end

-- ---------------------------------------------------------------------------
-- Збереження пари РНОКПП → ПІБ у кеш.
-- ---------------------------------------------------------------------------

local function save_pairs_to_cache(filepath, found_pairs)
    if not filepath or type(found_pairs) ~= "table" or vim.tbl_isempty(found_pairs) then
        return
    end

    local root = load_root_json()

    root.rnokpp_cache = root.rnokpp_cache or {}
    root.rnokpp_cache[filepath] =
        root.rnokpp_cache[filepath] or {}

    for rnokpp, fio in pairs(found_pairs) do
        root.rnokpp_cache[filepath][rnokpp] = fio
    end

    save_root_json(root)
end

-- ---------------------------------------------------------------------------
-- Отримання ПІБ за РНОКПП з кешу поточного файлу.
-- ---------------------------------------------------------------------------

function M.get_fio_from_lock(rnokpp)
    local filepath = get_current_filepath()

    if not filepath then
        return nil
    end

    local cache = load_rnokpp_cache_for_file(filepath)

    return cache[rnokpp]
end

-- ==================== ПАРСИНГ CSV ТА РЕЗУЛЬТАТІВ ====================

local function parse_csv_line(line)
    local fields = {}
    local current_field = ""
    local in_quotes = false
    local i = 1
    while i <= #line do
        local char = line:sub(i, i)
        if char == '"' then
            if in_quotes and line:sub(i + 1, i + 1) == '"' then
                current_field = current_field .. '"'
                i = i + 2
            else
                in_quotes = not in_quotes
                i = i + 1
            end
        elseif char == "," and not in_quotes then
            table.insert(fields, current_field)
            current_field = ""
            i = i + 1
        else
            current_field = current_field .. char
            i = i + 1
        end
    end
    table.insert(fields, current_field)
    return fields
end

local function extract_fio_from_line(line)
    line = line:gsub("^%b[]%s*", "", 1)

    local fields = parse_csv_line(line)

    local fio = vim.trim(fields[2] or "")

    if fio ~= "" then
        return fio
    end

    return nil
end

-- ==================== СТВОРЕННЯ ВІКНА ВИБОРУ ====================

function M.create_selection_window(items, target_win, target_buf, search_query, label_type)
    local buf = vim.api.nvim_create_buf(false, true)
    local formatted_items = {}

    for _, item in ipairs(items) do
        table.insert(formatted_items, string.format("[ ] %s", item))
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, formatted_items)

    local width = math.min(130, vim.o.columns - 10)
    local height = math.min(#items + 4, 15)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local title = string.format(" Результати (%d) ", #items)
    if search_query and search_query ~= "" then
        title = string.format(' Знайдено "%s" (%d) ', search_query, #items)
    end

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = title,
        title_pos = "center",
        footer = " <Space>: обрати │ <CR>: вставити │ q/<Esc>: вихід ",
        footer_pos = "center",
    })

    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"

    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].cursorline = true
    vim.wo[win].signcolumn = "no"

    -- Оновлення лічильника позиції у футері
    vim.api.nvim_create_autocmd("CursorMoved", {
        buffer = buf,
        callback = function()
            if not vim.api.nvim_win_is_valid(win) then return end
            local cur = vim.api.nvim_win_get_cursor(win)[1]
            local new_footer = string.format(" [%d/%d] │ <Space>: обрати │ <CR>: вставити │ q/<Esc>: вихід ", cur, #items)
            vim.api.nvim_win_set_config(win, { footer = new_footer, footer_pos = "center" })
        end,
    })

    local opts = { buffer = buf, silent = true }

    -- Перемикання вибору
    vim.keymap.set("n", "<Space>", function()
        local cur_row = vim.api.nvim_win_get_cursor(win)[1]
        local line = vim.api.nvim_buf_get_lines(buf, cur_row - 1, cur_row, false)[1]
        if line then
            if vim.startswith(line, "[ ]") then
                line = line:gsub("^%[%s%]", "[x]", 1)
            else
                line = line:gsub("^%[x%]", "[ ]", 1)
            end

            vim.api.nvim_buf_set_lines(buf, cur_row - 1, cur_row, false, { line })
            if cur_row < #formatted_items then
                vim.api.nvim_win_set_cursor(win, { cur_row + 1, 0 })
            end
        end
    end, opts)

    -- Підтвердження та вставка тексту
    vim.keymap.set("n", "<CR>", function()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local selected_texts = {}

        for _, line in ipairs(lines) do
            if vim.startswith(line, "[x]") then
                local clean = line:gsub("^%[x%]%s*", ""):gsub("^%[.-%]%s*", "")
                table.insert(selected_texts, clean)
            end
        end

        -- Якщо нічого не обрано, беремо поточний рядок
        if #selected_texts == 0 then
            local cur_row = vim.api.nvim_win_get_cursor(win)[1]
            local line = lines[cur_row]
            if line then
                local clean = line:gsub("^%[.%]%s*", ""):gsub("^%[.-%]%s*", "")
                table.insert(selected_texts, clean)
            end
        end

        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        vim.cmd("echo ''")

        if #selected_texts == 0 then return end

        local win_for_buf = nil
        for _, w in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_buf(w) == target_buf then
                win_for_buf = w
                break
            end
        end

        if win_for_buf and vim.bo[target_buf].modifiable then
            vim.api.nvim_set_current_win(win_for_buf)
            local r, c = unpack(vim.api.nvim_win_get_cursor(win_for_buf))
            local cur_line = vim.api.nvim_buf_get_lines(target_buf, r - 1, r, false)[1] or ""
            local text_to_insert = table.concat(selected_texts, " ")
            local new_line = cur_line:sub(1, c) .. text_to_insert .. cur_line:sub(c + 1)

            vim.api.nvim_buf_set_lines(target_buf, r - 1, r, false, { new_line })
            vim.cmd("redraw")
            vim.api.nvim_win_set_cursor(win_for_buf, { r, c + #text_to_insert })
            utils.info("✅ Успішно вставлено рядків: " .. #selected_texts)
        else
            utils.warn("⚠️ Поточне поле захищене від змін або вікно закрите.")
        end
    end, opts)

    -- Закриття вікна
    local close_win = function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        vim.cmd("echo ''")
    end

    vim.keymap.set("n", "q", close_win, opts)
    vim.keymap.set("n", "<Esc>", close_win, opts)
end

-- ==================== 1. ПОШУК В ДОКУМЕНТАХ ====================

function M.run_search()
    local default_query = extract_default_rnokpp()

    vim.ui.input({ prompt = "🔍 Пошук в ~/STATYSTYKA/shtat: ", default = default_query }, function(input)
        if not input or vim.trim(input) == "" then return end

        local function execute_search(password)
            local target_win = vim.api.nvim_get_current_win()
            local target_buf = vim.api.nvim_win_get_buf(target_win)

            vim.notify("⏳ Пошук в процесі...", vim.log.levels.INFO, { title = "Awards53" })

            vim.system(
                { SEARCHDOCS_PATH, input, SEARCH_DIR },
                { stdin = password ~= "" and (password .. "\n") or "\n" },
                function(obj)
                    vim.schedule(function()
                        if obj.code ~= 0 then
                            cached_passwords.gpg = nil
                            local err_msg = vim.trim(obj.stderr or "")
                            vim.notify(
                                "❌ Пошук завершився з помилкою (код: " .. tostring(obj.code) .. ")",
                                vim.log.levels.ERROR,
                                { title = "Awards53" }
                            )
                            if err_msg ~= "" then
                                utils.warn(err_msg)
                            end
                            return
                        end

                        local result = obj.stdout
                        if not result or vim.trim(result) == "" then
                            vim.notify("⚠️️ Пошук завершено: нічого не знайдено", vim.log.levels.WARN, { title = "Awards53" })
                            return
                        end

                        local items = {}
                        for _, line in ipairs(vim.split(result, "\n", { trimempty = true })) do
                            line = vim.trim(line)
                            if line ~= "" then
                                table.insert(items, line)
                            end
                        end

                        if #items == 0 then
                            vim.notify("⚠️ Пошук завершено: нічого не знайдено", vim.log.levels.WARN, { title = "Awards53" })
                            return
                        end

                        vim.notify("✅ Пошук завершено: знайдено " .. #items .. " результатів", vim.log.levels.INFO, { title = "Awards53" })
                        M.create_selection_window(items, target_win, target_buf, input, SEARCH_DIR)
                    end)
                end
            )
        end

        if cached_passwords.gpg then
            execute_search(cached_passwords.gpg)
        else
            local layout = get_keyboard_layout_indicator()
            local prompt_text = string.format("🔑 [%s] Введіть GPG пароль для розшифрування: ", layout)
            local password = vim.fn.inputsecret(prompt_text)
            print("")

            if password and password ~= "" then
                cached_passwords.gpg = password
            end

            execute_search(password or "")
        end
    end)
end

-- ==================== 2. ПОШУК У БД SQL ====================

function M.run_sql_search()
    local default_query = extract_default_rnokpp()

    vim.ui.input({ prompt = "🔍 Введіть запит для пошуку в БД: ", default = default_query }, function(input)
        if not input or vim.trim(input) == "" then return end

        local function execute_search(password)
            local target_win = vim.api.nvim_get_current_win()
            local target_buf = vim.api.nvim_win_get_buf(target_win)

            vim.notify("⏳ Пошук в базі даних...", vim.log.levels.INFO, { title = "Awards53" })

            vim.system(
                { SEARCHSQL_PATH, input, DB_PATH },
                { stdin = password ~= "" and (password .. "\n") or "\n" },
                function(obj)
                    vim.schedule(function()
                        if obj.code ~= 0 then
                            cached_passwords.db = nil
                            vim.notify("❌ Пошук в БД завершився з помилкою (код: " .. tostring(obj.code) .. ")", vim.log.levels.ERROR, { title = "Awards53" })
                            return
                        end

                        local result = obj.stdout
                        if not result or vim.trim(result) == "" then
                            vim.notify("⚠️ Нічого не знайдено", vim.log.levels.WARN, { title = "Awards53" })
                            return
                        end

                        local items = {}
                        for _, line in ipairs(vim.split(result, "\n", { trimempty = true })) do
                            table.insert(items, vim.trim(line))
                        end

                        vim.notify("✅ Знайдено записів: " .. #items, vim.log.levels.INFO, { title = "Awards53" })
                        M.create_selection_window(items, target_win, target_buf, input, "БД SQLCipher")
                    end)
                end
            )
        end

        if cached_passwords.db then
            execute_search(cached_passwords.db)
        else
            local layout = get_keyboard_layout_indicator()
            local prompt_text = string.format("🔑 [%s] Введіть пароль бази даних (SQLCipher): ", layout)
            local password = vim.fn.inputsecret(prompt_text)
            print("")

            if password and password ~= "" then
                cached_passwords.db = password
            end

            execute_search(password or "")
        end
    end)
end

-- ==================== 3. ПОШУК УСІХ РНОКПП В ORG ТА ЗАПИС У КЕШ ====================

function M.process_org_rnokpp_to_lock()
    local filepath = get_current_filepath()
    if not filepath then
        utils.warn("⚠️ Не вдалося визначити шлях до файла поточної сесії.")
        return
    end

    local state = require("awards53.state")
    local src_buf = state.get_source_buffer() or vim.api.nvim_get_current_buf()

    local lines = vim.api.nvim_buf_get_lines(src_buf, 0, -1, false)
    local cache = load_rnokpp_cache_for_file(filepath)

    local rnokpp_list = {}
    local seen = {}
    local total_found_in_text = 0

    for _, line in ipairs(lines) do
        for rnokpp in line:gmatch("(%d%d%d%d%d%d%d%d%d%d)") do
            total_found_in_text = total_found_in_text + 1
            if not seen[rnokpp] and not cache[rnokpp] then
                seen[rnokpp] = true
                table.insert(rnokpp_list, rnokpp)
            end
        end
    end

    vim.notify(
        string.format("📊 Знайдено в тексті: %d РНОКПП. Нових для пошуку: %d", total_found_in_text, #rnokpp_list),
        vim.log.levels.INFO,
        { title = "Awards53" }
    )

    if #rnokpp_list == 0 then
        if total_found_in_text > 0 then
            utils.info("ℹ️ Усі знайдені РНОКПП вже присутні у кеші для цього файла. Підказки активовано.")
            pcall(M.show_fio_near_rnokpp)
        else
            utils.warn("⚠️ У поточному буфері не знайдено жодного 10-значного РНОКПП.")
        end
        return
    end

    local function execute_batch(password)
        vim.notify(
            string.format(
                "🔍 Пошук %d РНОКПП ...",
                #rnokpp_list
            ),
            vim.log.levels.INFO,
            { title = "Awards53" }
        )

        local search_terms = table.concat(rnokpp_list, "|")

        vim.system(
            {
                SEARCHDOCS_PATH,
                search_terms,
                SEARCH_DIR,
            },
            {
                stdin = password .. "\n",
                text = true,
            },
            function(obj)
                vim.schedule(function()
                    if obj.code ~= 0 then
                        cached_passwords.gpg = nil

                        utils.warn(
                            "❌ Пошук завершився з помилкою: " ..
                            tostring(obj.code)
                        )

                        return
                    end

                    local result = obj.stdout or ""

                    if vim.trim(result) == "" then
                        utils.warn(
                            "⚠️ За жодним РНОКПП запис не знайдено."
                        )
                        return
                    end

                    -- Тут збираємо всі знайдені пари,
                    -- а JSON записуємо тільки один раз.
                    local found = {}

                    for _, line in ipairs(
                        vim.split(result, "\n", { trimempty = true })
                    ) do
                        line = vim.trim(line)

                        if line ~= "" then
                            local fio = extract_fio_from_line(line)

                            if fio then
                                for _, rnokpp in ipairs(rnokpp_list) do
                                    if not found[rnokpp]
                                        and line:find(rnokpp, 1, true)
                                    then
                                        found[rnokpp] = fio
                                    end
                                end
                            end
                        end
                    end

                    -- Один раз записуємо весь пакет у JSON.
                    save_pairs_to_cache(filepath, found)

                    local found_count = 0

                    for _ in pairs(found) do
                        found_count = found_count + 1
                    end

                    utils.info(
                        string.format(
                            "🎉 Опрацьовано %d РНОКПП. Додано у кеш: %d",
                            #rnokpp_list,
                            found_count
                        )
                    )

                    vim.cmd("redraw")
                    vim.defer_fn(function()
                        pcall(M.show_fio_near_rnokpp)
                    end, 50)
                end)
            end
        )
    end
    
    if cached_passwords.gpg then
        execute_batch(cached_passwords.gpg)
    else
        local layout = get_keyboard_layout_indicator()
        local password = vim.fn.inputsecret(string.format("🔑 [%s] Введіть пароль:", layout))

        vim.cmd("echo ''")
        vim.cmd("redraw")

        if password and password ~= "" then
            cached_passwords.gpg = password
            execute_batch(password)
        else
            utils.warn("❌ Пароль не введено")
        end
    end
end

-- ==================== 4. ВСТАВКА/ВІДОБРАЖЕННЯ ПІБ З КЕШУ ====================

local fio_ns = vim.api.nvim_create_namespace("awards53_fio_hint")

function M.show_fio_near_rnokpp()
    local filepath = get_current_filepath()
    if not filepath then
        return
    end

    local state = require("awards53.state")
    local ui = require("awards53.ui")

    local cache_data = load_rnokpp_cache_for_file(filepath)

    if not cache_data or vim.tbl_isempty(cache_data) then
        return
    end

    local cur_buf = vim.api.nvim_get_current_buf()

    -- ============================================================
    -- Сценарій А: UI карток Awards53
    -- ============================================================

    if ui.body_buf and cur_buf == ui.body_buf then
        local current_card_idx =
            ui.current_card or state.index() or 1

        local data = state.data()

        if not data
            or not data.records
            or not data.records[current_card_idx]
        then
            return
        end

        local card = data.records[current_card_idx]

        local rnokpp = nil

        -- Шукаємо РНОКПП у поточній картці.
        for _, lines in pairs(card) do
            if type(lines) == "table" then
                for _, line in ipairs(lines) do
                    local match =
                        line:match("(%d%d%d%d%d%d%d%d%d%d)")

                    if match and cache_data[match] then
                        rnokpp = match
                        break
                    end
                end
            elseif type(lines) == "string" then
                local match =
                    lines:match("(%d%d%d%d%d%d%d%d%d%d)")

                if match and cache_data[match] then
                    rnokpp = match
                    break
                end
            end

            if rnokpp then
                break
            end
        end

        if not rnokpp then
            return
        end

        local fio = cache_data[rnokpp]

        if not fio then
            return
        end

        -- Шукаємо рядок картки, біля якого показати ПІБ.
        local line_count =
            vim.api.nvim_buf_line_count(cur_buf)

        local target_row = nil

        for i = 0, line_count - 1 do
            local line_text =
                vim.api.nvim_buf_get_lines(
                    cur_buf,
                    i,
                    i + 1,
                    false
                )[1] or ""

            if line_text:match(rnokpp) then
                target_row = i
                break
            end
        end

        -- Якщо сам РНОКПП у відображеній картці не знайдений,
        -- використовуємо поточний рядок.
        if not target_row then
            target_row =
                vim.api.nvim_win_get_cursor(0)[1] - 1
        end

        vim.api.nvim_buf_clear_namespace(
            cur_buf,
            fio_ns,
            0,
            -1
        )

        vim.api.nvim_buf_set_extmark(
            cur_buf,
            fio_ns,
            target_row,
            0,
            {
                virt_text = {
                    { "  👤 " .. fio, "Comment" }
                },
                virt_text_pos = "eol",
            }
        )

        return
    end

    -- ============================================================
    -- Сценарій Б: звичайний .org буфер
    -- ============================================================

    local line_count =
        vim.api.nvim_buf_line_count(cur_buf)

    local cursor_row =
        vim.api.nvim_win_get_cursor(0)[1] - 1

    local rnokpp = nil
    local target_row = nil

    -- Спочатку шукаємо РНОКПП на поточному рядку.
    local current_line =
        vim.api.nvim_get_current_line()

    local current_rnokpp =
        current_line:match("(%d%d%d%d%d%d%d%d%d%d)")

    if current_rnokpp and cache_data[current_rnokpp] then
        rnokpp = current_rnokpp
        target_row = cursor_row
    end

    -- Якщо на поточному рядку його немає,
    -- шукаємо найближчий РНОКПП у всьому буфері.
    if not rnokpp then
        for i = 0, line_count - 1 do
            local line_text =
                vim.api.nvim_buf_get_lines(
                    cur_buf,
                    i,
                    i + 1,
                    false
                )[1] or ""

            local match =
                line_text:match("(%d%d%d%d%d%d%d%d%d%d)")

            if match and cache_data[match] then
                rnokpp = match
                target_row = i
                break
            end
        end
    end

    if not rnokpp or not target_row then
        return
    end

    local fio = cache_data[rnokpp]

    if not fio then
        return
    end

    vim.api.nvim_buf_clear_namespace(
        cur_buf,
        fio_ns,
        0,
        -1
    )

    vim.api.nvim_buf_set_extmark(
        cur_buf,
        fio_ns,
        target_row,
        0,
        {
            virt_text = {
                { "  👤 " .. fio, "Comment" }
            },
            virt_text_pos = "eol",
        }
    )
end

return M
