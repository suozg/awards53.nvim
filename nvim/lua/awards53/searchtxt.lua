local M = {}
local utils = require("awards53.utils")

-- Шляхи до скриптів та баз даних
local SEARCHDOCS_PATH = vim.fn.stdpath("config") .. "/bin/search.sh"
local SEARCH_DIR = vim.fn.expand("~/STATYSTYKA/shtat/300/") 

local SEARCHSQL_PATH = vim.fn.stdpath("config") .. "/bin/sql_search.sh"
local DB_PATH = vim.fn.expand("~/awards/awards_v4e.db")

-- Допоміжна функція для створення плаваючого вікна вибору результатів
local function create_selection_window(items, target_win, target_buf)
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
        title = " Виберіть рядки (<Space> - обрати, <CR> - вставити, q - вихід) ",
        title_pos = "center",
    })

    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"

    local opts = { buffer = buf, silent = true }

    -- 1. Пробіл становить/знімає позначку [x]
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

    -- 2. Enter підтверджує вибір та вставляє текст у редактор
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

    -- 3. Вихід по q
    vim.keymap.set("n", "q", function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, opts)
end

function M.run_search()
    vim.ui.input({ prompt = "🔍 Введіть текст для пошуку: " }, function(input)
        if not input or input == "" then return end

        local gpg_password = vim.fn.inputsecret("🔑 Введіть GPG пароль для розшифрування: ")
        print("")

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
                        local err_msg = vim.trim(obj.stderr or "")
                        if err_msg == "" then
                            err_msg = "Невідома помилка виконання скрипта (код: " .. tostring(obj.code) .. ")"
                        end
                        utils.warn("❌ " .. err_msg)
                        return
                    end

                    local result = obj.stdout
                    if not result or vim.trim(result) == "" then
                        utils.warn("⚠️ Нічого не знайдено за вашим запитом.")
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

                    create_selection_window(items, target_win, target_buf)
                end)
            end
        )
    end)
end

function M.run_sql_search()
    vim.ui.input({ prompt = "🔍 Введіть запит для пошуку в БД: " }, function(input)
        if not input or input == "" then return end

        local db_password = vim.fn.inputsecret("🔑 Введіть пароль бази даних (SQLCipher): ")
        print("")

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

                    create_selection_window(items, target_win, target_buf)
                end)
            end
        )
    end)
end

return M
