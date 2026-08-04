local M = {}
local utils = require("awards53.utils")

-- Шлях до скрипта у вашому конфізі
local SEARCHDOCS_PATH = vim.fn.stdpath("config") .. "/bin/search.sh"
-- Вкажіть ПОВНИЙ реальний шлях до папки з вашими документами та .gpg файлами
local SEARCH_DIR = vim.fn.expand("~/STATYSTYKA/shtat/300/") 

function M.run_search()
    vim.ui.input({ prompt = "🔍 Введіть текст для пошуку: " }, function(input)
        if not input or input == "" then return end

        local gpg_password = vim.fn.inputsecret("🔑 Введіть GPG пароль для розшифрування: ")
        print("")

        utils.info("⏳ Виконується пошук...")

        -- Запам'ятовуємо цільове вікно та буфер редактора ДО відкриття списку вибору
        local target_win = vim.api.nvim_get_current_win()
        local target_buf = vim.api.nvim_win_get_buf(target_win)

        vim.system(
            { SEARCHDOCS_PATH, input, SEARCH_DIR },
            {
                stdin = gpg_password ~= "" and (gpg_password .. "\n") or "\n",
            },
            function(obj)
                vim.schedule(function()
                    -- Якщо скрипт повернув помилку
                    if obj.code ~= 0 then
                        local err_msg = vim.trim(obj.stderr or "")
                        if err_msg == "" then
                            err_msg = "Невідома помилка виконання скрипта (код: " .. tostring(obj.code) .. ")"
                        end
                        utils.warn("❌ " .. err_msg)
                        print(err_msg)
                        return
                    end

                    local result = obj.stdout
                    if not result or vim.trim(result) == "" then
                        utils.warn("⚠️ Нічого не знайдено за вашим запитом.")
                        return
                    end

                    -- Збираємо рядки результатів
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

                    -- Створюємо тимчасовий буфер для інтерфейсу вибору
                    local buf = vim.api.nvim_create_buf(false, true)
                    local formatted_items = {}
                    for _, item in ipairs(items) do
                        table.insert(formatted_items, string.format("[ ] %s", item))
                    end
                    vim.api.nvim_buf_set_lines(buf, 0, -1, false, formatted_items)

                    -- Налаштування розмірів вікна вибору
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

                    -- 1. Натискання Пробілу становить/знімає позначку [x]
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

                    -- 2. Натискання Enter підтверджує вибір (один або кілька)
                    vim.keymap.set("n", "<CR>", function()
                        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                        local selected_texts = {}

                        -- Збираємо всі рядки, де поставлено [x]
                        for _, line in ipairs(lines) do
                            if vim.startswith(line, "[x]") then
                                -- Очищаємо від позначки та від префікса шляху [шлях]
                                local clean = line:gsub("^%[x%]%s*", ""):gsub("^%[.-%]%s*", "")
                                table.insert(selected_texts, clean)
                            end
                        end

                        -- Якщо галочки не ставили, але натиснули Enter на якомусь рядку — беремо поточний рядок
                        if #selected_texts == 0 then
                            local cur_row = vim.api.nvim_win_get_cursor(win)[1]
                            local line = lines[cur_row]
                            if line then
                                local clean = line:gsub("^%[.%]%s*", ""):gsub("^%[.-%]%s*", "")
                                table.insert(selected_texts, clean)
                            end
                        end

                        -- Закриваємо вікно вибору
                        if vim.api.nvim_win_is_valid(win) then
                            vim.api.nvim_win_close(win, true)
                        end

                        if #selected_texts == 0 then return end

                        -- Повертаємося до нашого редактора і вставляємо текст
                        if vim.api.nvim_win_is_valid(target_win) and vim.api.nvim_buf_is_valid(target_buf) then
                            vim.api.nvim_set_current_win(target_win)
                            
                            if vim.bo[target_buf].modifiable then
                                local r, c = unpack(vim.api.nvim_win_get_cursor(target_win))
                                local cur_line = vim.api.nvim_buf_get_lines(target_buf, r - 1, r, false)[1] or ""
                                
                                -- Об'єднуємо кілька вибраних результатів через пробіл (або змініть на "\n", якщо треба з нового рядка)
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
                end)
            end
        )
    end)
end

return M
