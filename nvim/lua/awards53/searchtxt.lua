-- searchtxt.lua
--
local M = {}
local utils = require("awards53.utils")
local uv = vim.uv or vim.loop

-- Шляхи до скриптів та баз даних
local SEARCHDOCS_PATH = vim.fn.stdpath("config") .. "/bin/search.sh"
local SEARCH_DIR = vim.fn.expand("~/STATYSTYKA/shtat/")

local SEARCHSQL_PATH = vim.fn.stdpath("config") .. "/bin/sql_search.sh"
local DB_PATH = vim.fn.expand("~/awards/awards_v4e.db")

-- Зберігання паролів у пам'яті сесії
local cached_passwords = {
    gpg = nil,
    db = nil,
}

-- Поточне повідомлення прогресу пошуку
local active_progress = nil
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

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
    if active_progress then
        stop_progress(active_progress)
    end

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
        vim.api.nvim_echo({ { message, "ModeMsg" } }, false, {})
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

-- Очищення кешу паролів
function M.clear_passwords()
    cached_passwords.gpg = nil
    cached_passwords.db = nil
    utils.info("🧹 Кеш паролів успішно очищено.")
end

-- Отримання індикатора розкладки клавіатури
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

-- Пошук РНОКПП у поточному записі для значення за замовчуванням
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

-- Створення плаваючого вікна вибору результатів
local function create_selection_window(items, target_win, target_buf, search_query, label_type)
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
        title = string.format(' Знайдено "%s" po %s (%d) ', search_query, label_type or SEARCH_DIR, #items)
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

    -- Перемикання вибору прапорцем [x]
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

        -- Якщо нічого не обрано через Space, беремо поточний рядок
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

-- Універсальна допоміжна функція виконання пошуку
local function prompt_and_search(cfg)
    local default_query = extract_default_rnokpp()

    vim.ui.input({ prompt = cfg.prompt, default = default_query }, function(input)
        if not input or vim.trim(input) == "" then return end

        local function execute_search(password)
            local target_win = vim.api.nvim_get_current_win()
            local target_buf = vim.api.nvim_win_get_buf(target_win)

            run_async_process(
                { cfg.script_path, input, cfg.target_path },
                { stdin = password ~= "" and (password .. "\n") or "\n" },
                cfg.label,
                function(obj, progress)
                    if obj.code ~= 0 then
                        cached_passwords[cfg.pass_key] = nil
                        finish_progress(progress, "❌ " .. cfg.label .. " завершився з помилкою (код: " .. tostring(obj.code) .. ")", vim.log.levels.ERROR)

                        local err_msg = vim.trim(obj.stderr or "")
                        if err_msg ~= "" then
                            utils.warn(err_msg)
                        end
                        return
                    end

                    local result = obj.stdout
                    if not result or vim.trim(result) == "" then
                        finish_progress(progress, "⚠️ Пошук завершено: нічого не знайдено", vim.log.levels.WARN)
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
                        finish_progress(progress, "⚠️ Пошук завершено: нічого не знайдено", vim.log.levels.WARN)
                        return
                    end

                    finish_progress(progress, "✅ Пошук завершено: знайдено " .. #items .. " результатів")
                    create_selection_window(items, target_win, target_buf, input, cfg.type_label)
                end
            )
        end

        if cached_passwords[cfg.pass_key] then
            execute_search(cached_passwords[cfg.pass_key])
        else
            local layout = get_keyboard_layout_indicator()
            local prompt_text = string.format("🔑 [%s] %s", layout, cfg.pass_prompt)
            local password = vim.fn.inputsecret(prompt_text)
            print("")

            if password and password ~= "" then
                cached_passwords[cfg.pass_key] = password
            end

            execute_search(password or "")
        end
    end)
end

function M.run_search()
    prompt_and_search({
        prompt = "🔍 Пошук в ~/STATISTIKA/shtat: ",
        pass_prompt = "Введіть GPG пароль для розшифрування: ",
        script_path = SEARCHDOCS_PATH,
        target_path = SEARCH_DIR,
        label = "Пошук у STATISTIKA",
        type_label = SEARCH_DIR,
        pass_key = "gpg",
    })
end

function M.run_sql_search()
    prompt_and_search({
        prompt = "🔍 Введіть запит для пошуку в БД: ",
        pass_prompt = "Введіть пароль бази даних (SQLCipher): ",
        script_path = SEARCHSQL_PATH,
        target_path = DB_PATH,
        label = "Пошук у базі SQLCipher",
        type_label = "БД SQLCipher",
        pass_key = "db",
    })
end

function M.process_all_rnokpp()
    M.run_search()
end

return M
