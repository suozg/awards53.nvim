-- search_with_lock.lua
-- Объединённый модуль поиска по файлу/SQL и работы с .lock записями

local M = {}
local utils = require("awards53.utils")
local uv = vim.uv or vim.loop

-- Шляхи до скриптів та баз даних
local SEARCHDOCS_PATH = vim.fn.stdpath("config") .. "/bin/search.sh"
local SEARCH_DIR = vim.fn.expand("~/STATYSTYKA/shtat/")

local SEARCHSQL_PATH = vim.fn.stdpath("config") .. "/bin/sql_search.sh"
local DB_PATH = vim.fn.expand("~/awards/awards_v4e.db")

-- Прапорець статусу обробки lock-файла (підказки не показуються, поки false)
M.lock_processed = false

-- Зберігання паролів у пам'яті сесії
local cached_passwords = {
    gpg = nil,
    db = nil,
}

local active_progress = nil
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- ==================== ПРОГРЕС ТА ПРОЦЕСИ ====================

local function stop_progress(progress)
    if not progress then return end
    progress.done = true
    if progress.timer then
        if not progress.timer:is_closing() then
            progress.timer:stop()
            progress.timer:close()
        end
        progress.timer = nil
    end
    if active_progress == progress then
        active_progress = nil
    end
end

local function start_progress(label)
    if active_progress then stop_progress(active_progress) end

    local progress = {
        label = label,
        frame = 0,
        started_at = uv.hrtime(),
        done = false,
        timer = uv.new_timer(),
    }
    active_progress = progress

    local function render()
        if progress.done then return end
        progress.frame = progress.frame % #spinner_frames + 1
        local elapsed = math.floor((uv.hrtime() - progress.started_at) / 1e9)
        local message = string.format("%s %s — %d с", spinner_frames[progress.frame], progress.label, elapsed)
        
        local save_more = vim.o.more
        vim.o.more = false
        vim.api.nvim_echo({ { message, "ModeMsg" } }, false, {})
        vim.o.more = save_more
    end

    render()
    progress.timer:start(500, 500, vim.schedule_wrap(render))
    return progress
end

local function finish_progress(progress, message, level)
    if not progress or progress.done then return end
    stop_progress(progress)
    vim.api.nvim_echo({ { "", "Normal" } }, false, {})
    vim.notify(message, level or vim.log.levels.INFO, {
        title = "Awards53",
        timeout = 3000,
    })
end

local function run_async_process(command, opts, label, callback)
    local progress = start_progress(label)
    local process = vim.system(command, opts, function(obj)
        vim.schedule(function()
            if progress.done then return end
            callback(obj, progress)
        end)
    end)
    progress.process = process
    return progress
end

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

-- ==================== Взаємодія з .lock файлом ====================

local function get_lock_file_path()
    local state = require("awards53.state")
    local src_buf = state.get_source_buffer() or vim.api.nvim_get_current_buf()
    local src_path = vim.api.nvim_buf_get_name(src_buf)
    if src_path == "" then return nil end
    return src_path .. ".awards53.lock"
end

local function load_lock_data(lock_file)
    if not lock_file or vim.fn.filereadable(lock_file) == 0 then
        return {}
    end
    
    local lines = vim.fn.readfile(lock_file)
    if not lines or #lines == 0 then
        return {}
    end
    
    local content = table.concat(lines, "\n")
    if vim.trim(content) == "" then 
        return {} 
    end
    
    local ok, parsed = pcall(vim.json.decode, content)
    if ok and type(parsed) == "table" then
        return parsed
    end
    
    return {}
end

local function save_pair_to_lock(lock_file, rnokpp, fio)
    if not lock_file then return false end
    local data = load_lock_data(lock_file)
    data[rnokpp] = fio
    local json_str = vim.json.encode(data)
    vim.fn.writefile(vim.split(json_str, "\n"), lock_file)
    return true
end

function M.get_fio_from_lock(rnokpp)
    local lock_file = get_lock_file_path()
    if not lock_file then return nil end
    local data = load_lock_data(lock_file)
    return data[rnokpp]
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

local function extract_fio_rnokpp_from_line(line, section_type)
    local fields = parse_csv_line(line)
    local fio_idx, rnokpp_idx
    if section_type == "alive" then
        fio_idx, rnokpp_idx = 2, 21
    elseif section_type == "excluded" then
        fio_idx, rnokpp_idx = 2, 17
    else
        return nil, nil
    end

    if #fields < math.max(fio_idx, rnokpp_idx) then return nil, nil end

    local fio = vim.trim(fields[fio_idx] or "")
    local rnokpp = vim.trim(fields[rnokpp_idx] or "")
    if fio ~= "" and rnokpp:match("^%d%d%d%d%d%d%d%d%d%d$") then
        return fio, rnokpp
    end
    return nil, nil
end

-- ==================== 1. ПОШУК ПО БАЗІ SQL ====================

function M.run_sql_search()
    local default_query = ""
    local state = require("awards53.state")
    local record = state.current_record()
    if record then
        for _, v in pairs(record) do
            local str = type(v) == "table" and table.concat(v, " ") or tostring(v)
            local m = str:match("(%d%d%d%d%d%d%d%d%d%d)")
            if m then default_query = m break end
        end
    end

    vim.ui.input({ prompt = "🔍 Введіть запит для пошуку в БД: ", default = default_query }, function(input)
        if not input or vim.trim(input) == "" then return end

        local function execute_search(password)
            local target_win = vim.api.nvim_get_current_win()
            local target_buf = vim.api.nvim_win_get_buf(target_win)

            run_async_process(
                { SEARCHSQL_PATH, input, DB_PATH },
                { stdin = password ~= "" and (password .. "\n") or "\n" },
                "Пошук у базі SQLCipher",
                function(obj, progress)
                    if obj.code ~= 0 then
                        cached_passwords.db = nil
                        finish_progress(progress, "❌ Пошук в БД завершився з помилкою", vim.log.levels.ERROR)
                        return
                    end
                    local result = obj.stdout
                    if not result or vim.trim(result) == "" then
                        finish_progress(progress, "⚠️ Нічого не знайдено", vim.log.levels.WARN)
                        return
                    end
                    local items = {}
                    for _, line in ipairs(vim.split(result, "\n", { trimempty = true })) do
                        table.insert(items, vim.trim(line))
                    end
                    finish_progress(progress, "✅ Знайдено записів: " .. #items)
                    M.create_selection_window(items, target_win, target_buf, input, "БД SQLCipher")
                end
            )
        end

        if cached_passwords.db then
            execute_search(cached_passwords.db)
        else
            local layout = get_keyboard_layout_indicator()
            local password = vim.fn.inputsecret(string.format("🔑 [%s] Введіть пароль БД (SQLCipher):", layout))
            print("")
            if password and password ~= "" then cached_passwords.db = password end
            execute_search(password or "")
        end
    end)
end

-- ==================== 2. ОБИЧНИЙ ПОШУК І ВИВІД У ВІКНО ====================

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

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = string.format(' Знайдено "%s" (%d) ', search_query, #items),
        title_pos = "center",
        footer = " <Space>: обрати │ <CR>: вставити │ q/<Esc>: вихід ",
        footer_pos = "center",
    })

    vim.bo[buf].buftype, vim.bo[buf].bufhidden = "nofile", "wipe"
    vim.wo[win].cursorline = true

    local opts = { buffer = buf, silent = true }
    vim.keymap.set("n", "<Space>", function()
        local cur_row = vim.api.nvim_win_get_cursor(win)[1]
        local line = vim.api.nvim_buf_get_lines(buf, cur_row - 1, cur_row, false)[1]
        if line then
            line = vim.startswith(line, "[ ]") and line:gsub("^%[%s%]", "[x]", 1) or line:gsub("^%[x%]", "[ ]", 1)
            vim.api.nvim_buf_set_lines(buf, cur_row - 1, cur_row, false, { line })
            if cur_row < #formatted_items then vim.api.nvim_win_set_cursor(win, { cur_row + 1, 0 }) end
        end
    end, opts)

    vim.keymap.set("n", "<CR>", function()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local selected_texts = {}
        for _, line in ipairs(lines) do
            if vim.startswith(line, "[x]") then
                table.insert(selected_texts, line:gsub("^%[x%]%s*", ""))
            end
        end
        if #selected_texts == 0 then
            local line = lines[vim.api.nvim_win_get_cursor(win)[1]]
            if line then table.insert(selected_texts, line:gsub("^%[.%]%s*", "")) end
        end

        if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
        if #selected_texts == 0 then return end

        if vim.bo[target_buf].modifiable then
            local r, c = unpack(vim.api.nvim_win_get_cursor(target_win))
            local cur_line = vim.api.nvim_buf_get_lines(target_buf, r - 1, r, false)[1] or ""
            local text_to_insert = table.concat(selected_texts, " ")
            local new_line = cur_line:sub(1, c) .. text_to_insert .. cur_line:sub(c + 1)
            vim.api.nvim_buf_set_lines(target_buf, r - 1, r, false, { new_line })
            utils.info("✅ Вставлено елементів: " .. #selected_texts)
        end
    end, opts)

    local close_win = function() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end end
    vim.keymap.set("n", "q", close_win, opts)
    vim.keymap.set("n", "<Esc>", close_win, opts)
end

function M.run_search()
    vim.ui.input({ prompt = "🔍 Пошук в ~/STATYSTYKA/shtat: " }, function(input)
        if not input or vim.trim(input) == "" then return end

        local function execute_search(password)
            local target_win = vim.api.nvim_get_current_win()
            local target_buf = vim.api.nvim_win_get_buf(target_win)

            run_async_process(
                { SEARCHDOCS_PATH, input, SEARCH_DIR },
                { stdin = password ~= "" and (password .. "\n") or "\n" },
                "Пошук у STATYSTYKA",
                function(obj, progress)
                    if obj.code ~= 0 then
                        cached_passwords.gpg = nil
                        finish_progress(progress, "❌ Пошук завершився з помилкою", vim.log.levels.ERROR)
                        return
                    end
                    local result = obj.stdout
                    if not result or vim.trim(result) == "" then
                        finish_progress(progress, "⚠️ Нічого не знайдено", vim.log.levels.WARN)
                        return
                    end
                    local items = {}
                    for _, line in ipairs(vim.split(result, "\n", { trimempty = true })) do
                        table.insert(items, vim.trim(line))
                    end
                    finish_progress(progress, "✅ Знайдено: " .. #items)
                    M.create_selection_window(items, target_win, target_buf, input, SEARCH_DIR)
                end
            )
        end

        if cached_passwords.gpg then
            execute_search(cached_passwords.gpg)
        else
            local layout = get_keyboard_layout_indicator()
            local password = vim.fn.inputsecret(string.format("🔑 [%s] Введіть GPG пароль:", layout))
            print("")
            if password and password ~= "" then cached_passwords.gpg = password end
            execute_search(password or "")
        end
    end)
end

-- ==================== 3. ПОШУК УСІХ РНОКПП В ORG ТА ЗАПИС У .LOCK ====================

function M.process_org_rnokpp_to_lock()
    local state = require("awards53.state")
    local src_buf = state.get_source_buffer() or vim.api.nvim_get_current_buf()
    local src_path = vim.api.nvim_buf_get_name(src_buf)

    if not src_path or src_path == "" then
        utils.warn("❌ Помилка: Поточний буфер не збережено на диск (немає шляху до файла).")
        return
    end

    local lock_file = src_path .. ".awards53.lock"

    local lines = vim.api.nvim_buf_get_lines(src_buf, 0, -1, false)
    local existing_lock = load_lock_data(lock_file)
    if type(existing_lock) ~= "table" then
        existing_lock = {}
    end

    local rnokpp_list = {}
    local seen = {}
    local total_found_in_text = 0

    for _, line in ipairs(lines) do
        for rnokpp in line:gmatch("(%d%d%d%d%d%d%d%d%d%d)") do
            total_found_in_text = total_found_in_text + 1
            if not seen[rnokpp] and not existing_lock[rnokpp] then
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
        -- Якщо нових немає, але РНОКПП взагалі знайдені, активуємо прапорець показу ПІБ
        if total_found_in_text > 0 then
            M.lock_processed = true
            utils.info("ℹ️ Усі знайдені РНОКПП вже присутні у .lock файлі. Підказки активовано.")
            pcall(M.show_fio_near_rnokpp)
        else
            utils.warn("⚠️ У поточному буфері не знайдено жодного 10-значного РНОКПП.")
        end
        return
    end

    local function execute_batch(password)
        local total = #rnokpp_list
        local found_count = 0

        local function process_next(index)
            if index > total then
                -- Повідомляємо модуль, що обробку Lock повністю завершено
                M.lock_processed = true
                utils.info(string.format("🎉 Завершено! Опрацьовано %d РНОКПП. Додано у .lock: %d", total, found_count))
                
                -- Автоматично оновлюємо підказки після завершення
                pcall(M.show_fio_near_rnokpp)
                return
            end

            local cur_rnokpp = rnokpp_list[index]
            run_async_process(
                { SEARCHDOCS_PATH, cur_rnokpp, SEARCH_DIR },
                { stdin = password .. "\n" },
                string.format("Пошук [%d/%d]: %s", index, total, cur_rnokpp),
                function(obj, progress)
                    if obj.code == 0 and obj.stdout then
                        local section_type = nil
                        for _, line in ipairs(vim.split(obj.stdout, "\n", { trimempty = true })) do
                            line = vim.trim(line)
                            if line:find("живих людей") or line:find("Облік особового складу") then
                                section_type = "alive"
                            elseif line:find("виключен") or line:find("Виключен") then
                                section_type = "excluded"
                            end

                            local fio, r = extract_fio_rnokpp_from_line(line, section_type)
                            if fio and r == cur_rnokpp then
                                save_pair_to_lock(lock_file, cur_rnokpp, fio)
                                found_count = found_count + 1
                                break
                            end
                        end
                    end
                    finish_progress(progress, string.format("Опрацьовано %s", cur_rnokpp))
                    process_next(index + 1)
                end
            )
        end

        vim.schedule(function()
            process_next(1)
        end)
    end

    if cached_passwords.gpg then
        execute_batch(cached_passwords.gpg)
    else
        local layout = get_keyboard_layout_indicator()
        local password = vim.fn.inputsecret(string.format("🔑 [%s] Введіть GPG пароль:", layout))
        
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

-- ==================== 4. ВСТАВКА/ВІДОБРАЖЕННЯ ПІБ З .LOCK ====================

local fio_ns = vim.api.nvim_create_namespace("awards53_fio_hint")

function M.show_fio_near_rnokpp()
    -- Якщо процес обробки Lock ще не запускався, нічого не відображаємо
    if not M.lock_processed then
        return
    end

    local state = require("awards53.state")
    local ui = require("awards53.ui")
    
    local src_buf = state.get_source_buffer() or vim.api.nvim_get_current_buf()
    local src_path = vim.api.nvim_buf_get_name(src_buf)
    
    if not src_path or src_path == "" then return end

    local lock_file = src_path .. ".awards53.lock"
    local lock_data = load_lock_data(lock_file)

    if not lock_data or vim.tbl_isempty(lock_data) then return end

    local cur_buf = vim.api.nvim_get_current_buf()

    -- ==================== СЦЕНАРІЙ А: UI КАРТОК (ui.body_buf) ====================
    if ui.body_buf and cur_buf == ui.body_buf then
        local current_card_idx = ui.current_card or state.index() or 1
        local data = state.data()
        
        if not data or not data.records or not data.records[current_card_idx] then return end

        local card = data.records[current_card_idx]
        local rnokpp = nil

        for _, lines in pairs(card) do
            if type(lines) == "table" then
                for _, line in ipairs(lines) do
                    local match = line:match("(%d%d%d%d%d%d%d%d%d%d)")
                    if match then
                        rnokpp = match
                        break
                    end
                end
            end
            if rnokpp then break end
        end

        if not rnokpp then return end

        local fio = lock_data[rnokpp]
        if not fio then return end

        local line_count = vim.api.nvim_buf_line_count(cur_buf)
        local target_row = nil

        for i = 0, line_count - 1 do
            local line_text = vim.api.nvim_buf_get_lines(cur_buf, i, i + 1, false)[1] or ""
            if line_text:match("%d%d%.%d%d%.%d%d%d%d") or line_text:match("н%.р") or line_text:match("д%.н") then
                target_row = i
                break
            elseif line_text:match(rnokpp) then
                target_row = i
            end
        end

        if not target_row then
            target_row = vim.api.nvim_win_get_cursor(0)[1] - 1
        end

        vim.api.nvim_buf_clear_namespace(cur_buf, fio_ns, 0, -1)

        vim.api.nvim_buf_set_extmark(cur_buf, fio_ns, target_row, 0, {
            virt_text = { { "  👤 " .. fio, "Comment" } },
            virt_text_pos = "eol",
        })
        return
    end

    -- ==================== СЦЕНАРІЙ Б: ЗВИЧАЙНИЙ .ORG БУФЕР ====================
    local line_idx = vim.api.nvim_win_get_cursor(0)[1] - 1
    local line = vim.api.nvim_get_current_line()
    local rnokpp = line:match("(%d%d%d%d%d%d%d%d%d%d)")

    if not rnokpp then return end

    local fio = lock_data[rnokpp]
    if not fio then return end

    vim.api.nvim_buf_clear_namespace(cur_buf, fio_ns, 0, -1)
    vim.api.nvim_buf_set_extmark(cur_buf, fio_ns, line_idx, 0, {
        virt_text = { { "  👤 " .. fio, "Comment" } },
        virt_text_pos = "eol",
    })
end

-- Алиас для удобного вызова из `ui.redraw()`
M.render_fio_hint = M.show_fio_near_rnokpp

function M.clear_passwords()
    cached_passwords.gpg = nil
    cached_passwords.db = nil
    utils.info("🧹 Кеш паролів очищено")
end

return M
