local M = {}
local utils = require("awards53.utils")

-- Шляхи до скриптів та баз даних
local SEARCHDOCS_PATH = vim.fn.stdpath("config") .. "/bin/search.sh"
local SEARCH_DIR = vim.fn.expand("~/STATYSTYKA/shtat/") 

local SEARCHSQL_PATH = vim.fn.stdpath("config") .. "/bin/sql_search.sh"
local DB_PATH = vim.fn.expand("~/awards/awards_v4e.db")

-- Шлях до вашого скрипта розкладки
local KEYBOARD_SCRIPT_PATH = vim.fn.stdpath("config") .. "/bin/keyboard_script.sh"

-- Зберігання паролів у пам'яті сесії
local cached_gpg_password = nil
local cached_db_password = nil

-- Функція для примусового скидання кешованих паролів
function M.clear_passwords()
    cached_gpg_password = nil
    cached_db_password = nil
    utils.info("🧹 Кеш паролів успішно очищено. Наступного разу буде запитано наново.")
end

-- Функція для отримання актуального значка поточної розкладки напряму з системи
local function get_keyboard_layout_indicator()
    local handle = io.popen("xkb-switch -p")
    if handle then
        local current = handle:read("*a")
        handle:close()
        current = vim.trim(current)
        if current == "ua" then
            return "🌻UA"
        end
    end
    return "🗽US"
end

-- Допоміжна функція для створення плаваючого вікна вибору результатів із підсвіткою
local function create_selection_window(items, target_win, target_buf, search_query, search_type_label)
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

    -- Формуємо заголовок вікна
    local label = search_type_label or SEARCH_DIR
    local title_local = string.format(" Результати (%d) ", #items)
    if search_query and search_query ~= "" then
        title_local = string.format(' Знайдено "%s" по %s (%d) ', search_query, label, #items)
    end

    -- 1. СПОЧАТКУ створюємо вікно, щоб змінна `win` отримала коректний числовий ID
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = title_local,
        title_pos = "center",
        footer = " <Space>: обрати │ <CR>: вставити │ q: вихід ",
        footer_pos = "center",
    })

    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"

    -- Налаштування вікна
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].cursorline = true
    vim.wo[win].signcolumn = "no"

    -- 2. ТУТ створюємо автокоманду ПІСЛЯ створення вікна (те `win` вже існує)
    vim.api.nvim_create_autocmd("CursorMoved", {
        buffer = buf,
        callback = function()
            if not vim.api.nvim_win_is_valid(win) then return end
            local cur = vim.api.nvim_win_get_cursor(win)[1]
            local total = #items
            local new_footer = string.format(" [%d/%d] │ <Space>: обрати │ <CR>: вставити │ q: вихід ", cur, total)
            vim.api.nvim_win_set_config(win, {
                footer = new_footer,
                footer_pos = "center"
            })
        end,
    })
    
    -- Додаємо підсвітку іскомого слова/РНОКПП у вікні результатів
    if search_query and search_query ~= "" then
        local ns_id = vim.api.nvim_create_namespace("awards53_search_highlight")
        vim.cmd("highlight default link Awards53Match IncSearch")

        for i, line in ipairs(formatted_items) do
            local start_idx, end_idx = line:lower():find(search_query:lower(), 1, true)
            if start_idx then
                vim.api.nvim_buf_add_highlight(buf, ns_id, "Awards53Match", i - 1, start_idx - 1, end_idx)
            end
        end
    end

    local opts = { buffer = buf, silent = true }

    vim.keymap.set("n", "<Space>", function()
        local cur_row = vim.api.nvim_win_get_cursor(win)[1]
        local line = vim.api.nvim_buf_get_lines(buf, cur_row - 1, cur_row, false)[1]
        if line then
            if vim.startswith(line, "[ ]") then
                line = line:gsub("%[%s%]", "[x]", 1)
            else
                line = line:gsub("%[x%]", "[ ]", 1)
            end
            vim.api.nvim_buf_set_lines(buf, cur_row - 1, cur_row, false, { line })
            if cur_row < #formatted_items then
                vim.api.nvim_win_set_cursor(win, { cur_row + 1, 0 })
            end
        end
    end, opts)

    vim.keymap.set("n", "<CR>", function()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local selected_texts = {}

        for _, line in ipairs(lines) do
            if vim.startswith(line, "[x]") then
                local clean = line:gsub("^%[x%]%s*", ""):gsub("^%[.-%]%s*", "")
                table.insert(selected_texts, clean)
            end
        end

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

        if vim.api.nvim_win_is_valid(target_win) and vim.api.nvim_buf_is_valid(target_buf) then
            vim.api.nvim_set_current_win(target_win)
            
            if vim.bo[target_buf].modifiable then
                local r, c = unpack(vim.api.nvim_win_get_cursor(target_win))
                local cur_line = vim.api.nvim_buf_get_lines(target_buf, r - 1, r, false)[1] or ""
                local text_to_insert = table.concat(selected_texts, " ")
                local new_line = cur_line:sub(1, c) .. text_to_insert .. cur_line:sub(c + 1)

                vim.api.nvim_buf_set_lines(target_buf, r - 1, r, false, { new_line })
                vim.cmd("redraw")
                vim.api.nvim_win_set_cursor(target_win, { r, c + #text_to_insert })
                utils.info("✅ Успішно вставлено рядків: " .. #selected_texts)
            else
                utils.warn("⚠️ Поточне поле захищене від змін.")
            end
        end
    end, opts)

    vim.keymap.set("n", "q", function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        vim.cmd("echo ''")
    end, opts)
end

function M.run_search()
    local state = require("awards53.state")
    local record = state.current_record()
    
    local default_query = ""
    if record then
        local card_text = ""
        for _, field_val in pairs(record) do
            if type(field_val) == "table" then
                card_text = card_text .. " " .. table.concat(field_val, " ")
            elseif type(field_val) == "string" then
                card_text = card_text .. " " .. field_val
            end
        end
        local rnokpp_start, rnokpp_end = card_text:find("(%d%d%d%d%d%d%d%d%d%d)")
        if rnokpp_start then
            default_query = card_text:sub(rnokpp_start, rnokpp_end)
        end
    end

    vim.ui.input({ prompt = "🔍 Пошук в ~/STATISTIKA/shtat: ", default = default_query }, function(input)
        if not input or vim.trim(input) == "" then return end

        local function proceed_with_password(gpg_password)
            utils.info("⏳ Виконується пошук...")

            local target_win = vim.api.nvim_get_current_win()
            local target_buf = vim.api.nvim_win_get_buf(target_win)

            vim.system(
                { SEARCHDOCS_PATH, input, SEARCH_DIR },
                {
                    stdin = gpg_password ~= "" and (gpg_password .. "\n") or "\n",
                },
                function(obj)
                    vim.schedule(function()
                        if obj.code ~= 0 then
                            cached_gpg_password = nil
                            local err_msg = vim.trim(obj.stderr or "")
                            if err_msg == "" then
                                err_msg = "Невідома помилка виконання скрипта (код: " .. tostring(obj.code) .. ")"
                            end
                            utils.warn("❌ " .. err_msg)
                            return
                        end

                        local result = obj.stdout
                        if not result or vim.trim(result) == "" then
                            utils.warn("⚠️ Нічого не знайдено за запитом: " .. input)
                            return
                        end

                        local items = {}
                        for line in result:gmatch("[^\r\n]+") do
                            if vim.trim(line) ~= "" then
                                table.insert(items, vim.trim(line))
                            end
                        end

                        if #items == 0 then
                            utils.warn("⚠️ Нічого не знайдено.")
                            return
                        end

                        create_selection_window(items, target_win, target_buf, input, SEARCH_DIR)
                    end)
                end
            )
        end

        if cached_gpg_password then
            proceed_with_password(cached_gpg_password)
        else
            local layout = get_keyboard_layout_indicator()
            local prompt_text = string.format("🔑 [%s] Введіть GPG пароль для розшифрування: ", layout)
            local gpg_password = vim.fn.inputsecret(prompt_text)
            print("")
            if gpg_password ~= "" then
                cached_gpg_password = gpg_password
            end
            proceed_with_password(gpg_password)
        end
    end)
end

function M.process_all_rnokpp()
    M.run_search()
end

function M.run_sql_search()
    local state = require("awards53.state")
    local record = state.current_record()
    
    local default_query = ""
    if record then
        local card_text = ""
        for _, field_val in pairs(record) do
            if type(field_val) == "table" then
                card_text = card_text .. " " .. table.concat(field_val, " ")
            elseif type(field_val) == "string" then
                card_text = card_text .. " " .. field_val
            end
        end
        local rnokpp_start, rnokpp_end = card_text:find("(%d%d%d%d%d%d%d%d%d%d)")
        if rnokpp_start then
            default_query = card_text:sub(rnokpp_start, rnokpp_end)
        end
    end

    vim.ui.input({ prompt = "🔍 Введіть запит для пошуку в БД: ", default = default_query }, function(input)
        if not input or vim.trim(input) == "" then
            return
        end

        local function proceed_with_sql_password(db_password)
            utils.info("⏳ Виконується запит до бази даних...")

            local target_win = vim.api.nvim_get_current_win()
            local target_buf = vim.api.nvim_win_get_buf(target_win)

            vim.system(
                { SEARCHSQL_PATH, input, DB_PATH },
                {
                    stdin = db_password ~= "" and (db_password .. "\n") or "\n",
                },
                function(obj)
                    vim.schedule(function()
                        if obj.code ~= 0 then
                            cached_db_password = nil
                            local err_msg = vim.trim(obj.stderr or "")
                            if err_msg == "" then
                                err_msg = "Помилка виконання SQL-скрипта (код: " .. tostring(obj.code) .. ")"
                            end
                            utils.warn("❌ " .. err_msg)
                            return
                        end

                        local result = obj.stdout
                        if not result or vim.trim(result) == "" then
                            utils.warn("⚠️ Нічого не знайдено в базі даних.")
                            return
                        end

                        local items = {}
                        for line in result:gmatch("[^\r\n]+") do
                            if vim.trim(line) ~= "" then
                                table.insert(items, vim.trim(line))
                            end
                        end

                        if #items == 0 then
                            utils.warn("⚠️ Нічого не знайдено.")
                            return
                        end

                        create_selection_window(items, target_win, target_buf, input, "БД SQLCipher")
                    end)
                end
            )
        end

        if cached_db_password then
            proceed_with_sql_password(cached_db_password)
        else
            local layout = get_keyboard_layout_indicator()
            local prompt_text = string.format("🔑 [%s] Введіть пароль бази даних (SQLCipher): ", layout)
            local db_password = vim.fn.inputsecret(prompt_text)
            print("")
            if db_password ~= "" then
                cached_db_password = db_password
            end
            proceed_with_sql_password(db_password)
        end
    end)
end

label_end = true
return M
