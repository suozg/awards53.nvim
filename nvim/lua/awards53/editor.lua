local M = {}

local state = require("awards53.state")
local utils = require("awards53.utils")
local actions = require("awards53.actions")

M.buf = nil      -- Буфер редагування тексту
M.win = nil      -- Вікно редагування тексту
M.help_buf = nil -- Буфер підказок
M.help_win = nil -- Вікно підказок внизу

local help_lines = {
    "  R   - Форматувати РНОКПП/ВЧ у поточному полі           |  e   - Склеїти рядки поточного поля в один рядок",
    "  X   - Форматувати РНОКПП/ВЧ у цьому полі ВСІХ КАРТОК   |  E   - Склеїти рядки цього поля у ВСІХ картках файлу",
    "  :w  - Зберегти зміни    │   :q  - Зберегти та вийти    │  :q! - Вийти без збереження",
}

-- -----------------------------------------------------------------------------
-- ДОПОМІЖНІ ФУНКЦІЇ
-- -----------------------------------------------------------------------------
local function get_text_stats()
    if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
        return { lines = 0, words = 0, chars = 0 }
    end

    local lines = vim.api.nvim_buf_get_lines(M.buf, 0, -1, false)
    local line_count = #lines
    local word_count = 0
    local char_count = 0

    for _, line in ipairs(lines) do
        char_count = char_count + vim.str_utfindex(line)
        -- Шукаємо будь-які блоки без пробілів
        for _ in string.gmatch(line, "%S+") do
            word_count = word_count + 1
        end
    end

    return { lines = line_count, words = word_count, chars = char_count }
end

local function setup_help_window()
    if M.help_win and vim.api.nvim_win_is_valid(M.help_win) then return end

    vim.schedule(function()
        -- Повторна перевірка всередині schedule на випадок, якщо вікно вже створилося
        if M.help_win and vim.api.nvim_win_is_valid(M.help_win) then return end

        if not (M.help_buf and vim.api.nvim_buf_is_valid(M.help_buf)) then
            M.help_buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(M.help_buf, 0, -1, false, help_lines)
            local h_bo = vim.bo[M.help_buf]
            h_bo.buftype, h_bo.bufhidden, h_bo.swapfile, h_bo.modifiable = "nofile", "hide", false, false
        end

        -- Безпечне створення вікна через pcall
        local ok, win = pcall(vim.api.nvim_open_win, M.help_buf, false, {
            split = "below",
            height = #help_lines,
            win = -1,
        })

        -- Якщо створення вікна не вдалося (повернуло false) або ID некоректне
        if not ok or not win or not vim.api.nvim_win_is_valid(win) then
            return
        end

        M.help_win = win

        local h_wo = vim.wo[M.help_win]
        h_wo.number, h_wo.relativenumber, h_wo.signcolumn, h_wo.colorcolumn, h_wo.spell = false, false, "no", "", false
        h_wo.winfixheight = true
        h_wo.statusline = "%!v:lua.require'awards53.editor'.render_help_status()"
        h_wo.winhighlight = "Normal:Awards53Help,NormalNC:Awards53Help,SignColumn:Awards53Help"

        vim.api.nvim_set_hl(0, "Awards53Help", { fg = "#897d6d", bg = "#3C3838" })
        vim.api.nvim_set_hl(0, "Awards53HelpText", { fg = "#897d6d", bg = "#3C3838", bold = false })

        local ns = vim.api.nvim_create_namespace("awards53_editor_help")
        for i = 0, #help_lines - 1 do
            vim.api.nvim_buf_add_highlight(M.help_buf, ns, "Awards53EditorHelpText", i, 0, -1)
        end
    end)
end

local function close_help_window()
    if M.help_win and vim.api.nvim_win_is_valid(M.help_win) then
        pcall(vim.api.nvim_win_close, M.help_win, true)
        M.help_win = nil
    end
end

local function get_prev_field_preview()
    local record = state.current_record()
    if not record then return "" end

    local field_idx = state.field_index()
    if not field_idx or field_idx <= 1 then return "" end

    local headers = state.headers_list()
    local first_field_name = headers[1]
    if not first_field_name then return "" end

    local first_field_data = record[first_field_name]

    if first_field_data and #first_field_data > 0 then
        local first_line = vim.trim(first_field_data[1] or "")
        if first_line ~= "" then
            if vim.fn.strchars(first_line) > 20 then
                first_line = vim.fn.strcharpart(first_line, 0, 30) .. ""
            end
            return string.format(" 👈: %s", first_line)
        end
    end

    return ""
end

-- Отримання красивого опису (назва картки та номер поля) для сповіщень
local function get_editor_context_name(buf_id)
    buf_id = buf_id or M.buf
    if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then return "потоку" end

    local record = state.current_record()
    local field = state.field_name()
    local first_field_text = ""

    local headers = state.headers_list()
    local first_field_name = headers[1]

    if first_field_name and record and record[first_field_name] and #record[first_field_name] > 0 then
        first_field_text = vim.trim(record[first_field_name][1] or "")
        if first_field_text ~= "" and vim.fn.strchars(first_field_text) > 20 then
            first_field_text = vim.fn.strcharpart(first_field_text, 0, 20) .. "…"
        end
    end

    if first_field_text ~= "" then
        return string.format("полі '%s' картки '%s'", field, first_field_text)
    else
        return string.format("полі '%s' картки №%d", field, state.index())
    end
end

-- Динамічне оновлення назви буфера редактора для mini.tabline із позначкою '*'
local function update_buffer_title()
    if not M.buf or type(M.buf) ~= "number" or not vim.api.nvim_buf_is_valid(M.buf) then return end

    local record = state.current_record()
    if not record then return end

    local field = state.field_name()
    local first_field_text = ""
    local headers = state.headers_list()
    local first_field_name = headers[1]

    if first_field_name and record[first_field_name] and #record[first_field_name] > 0 then
        first_field_text = vim.trim(record[first_field_name][1] or "")
        if first_field_text ~= "" and vim.fn.strchars(first_field_text) > 18 then
            first_field_text = vim.fn.strcharpart(first_field_text, 0, 18) .. "…"
        end
    end

    local base_title = ""
    if first_field_text ~= "" then
        base_title = string.format("%s (поле %s)", first_field_text, field)
    else
        base_title = string.format("Картка %d (поле %s)", state.index(), field)
    end

    local is_modified = vim.bo[M.buf].modified
    local prefix = is_modified and "* " or ""
    local buf_title = prefix .. base_title

    pcall(vim.api.nvim_buf_set_name, M.buf, buf_title)
end

-- -----------------------------------------------------------------------------
-- ГОЛОВНА ФУНКЦІЯ ВІДКРИТТЯ РЕДАКТОРА
-- -----------------------------------------------------------------------------

function M.open()
    local record = state.current_record()
    local field = state.field_name()

    -- 1. Створюємо буфер редагування
    M.buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(0, M.buf)
    M.win = vim.api.nvim_get_current_win()

    local bo = vim.bo[M.buf]
    bo.bufhidden, bo.swapfile, bo.filetype, bo.spelllang = "hide", false, "org", "uk,en"
    bo.buftype = "acwrite"

    -- 2. Записуємо текст поля в буфер
    local content_lines = vim.deepcopy(record[field] or {})
    if #content_lines == 0 then content_lines = { "" } end
    vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, content_lines)
    require("awards53.abbreviations").register_buffer_abbreviations(M.buf)

    -- ВАЖЛИВО: Скидаємо modified ПІСЛЯ запису початкових рядків
    bo.modified = false

    -- 3. Формуємо назву буфера
    update_buffer_title()

    vim.api.nvim_win_set_cursor(M.win, { 1, 0 })

    local wo = vim.wo[M.win]
    wo.spell, wo.statusline = true, "%!v:lua.require'awards53.editor'.render_status()"

    setup_help_window()

    local group = vim.api.nvim_create_augroup("Awards53Editor", { clear = true })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = M.buf, 
        group = group, 
        callback = function() 
            update_buffer_title()
            vim.cmd("redrawstatus!") 
        end,
    })

    local function save_and_notify()
        M.save_core()
        utils.info("Зміни збережено в org-файл!")
    end

    -- Обробник збереження для buftype = acwrite
    vim.api.nvim_create_autocmd("BufWriteCmd", { 
        buffer = M.buf, 
        group = group, 
        callback = save_and_notify 
    })
    
    vim.api.nvim_buf_create_user_command(M.buf, "W", save_and_notify, {})

    -- Команда закриття :Q
    vim.api.nvim_buf_create_user_command(M.buf, "Q", function(opts)
        local target_buf = M.buf
        if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then return end

        local is_modified = vim.bo[target_buf].modified

        if is_modified and not opts.bang then
            local context_info = get_editor_context_name(target_buf)
            utils.warn(string.format(
                "⚠️ Є незбережені зміни в %s! Використайте :w для збереження або :q! для скасування.", 
                context_info
            ))
            return
        end

        if opts.bang and not state.is_changed then
            local src = state.get_source_buffer()
            if src and vim.api.nvim_buf_is_valid(src) then
                vim.bo[src].modified = false
            end
        end

        close_help_window()

        M.buf = nil 

        local ui = require("awards53.ui")
        ui.close_editor()

        if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
            pcall(vim.api.nvim_buf_delete, target_buf, { force = true })
        end

        ui.redraw()
    end, { bang = true })

    vim.cmd("cnoreabbrev <buffer> q Q")
    vim.cmd("cnoreabbrev <buffer> q! Q!")
    vim.cmd("cnoreabbrev <buffer> w W")
    vim.cmd("cnoreabbrev <buffer> w! W!")
    vim.cmd("cnoreabbrev <buffer> й Q")
    vim.cmd("cnoreabbrev <buffer> й! Q!")
    vim.cmd("cnoreabbrev <buffer> ц W")
    vim.cmd("cnoreabbrev <buffer> ц! W!")   

    local editor_keymaps = {
        ["R"] = { function() M.save_core(true) actions.format_rnokpp_in_current_card() M.refresh_editor_buffer() end, nil },
        ["X"] = { function() M.save_core(true) actions.format_rnokpp_in_all_cards() M.refresh_editor_buffer() end, nil },
        ["e"] = { function() M.save_core(true) state.flatten_current_field() M.refresh_editor_buffer() end, nil },
        ["E"] = { function() M.save_core(true) state.flatten_field_globally() M.refresh_editor_buffer() end, nil },
    }

    local key_opts = { buffer = M.buf, silent = true, noremap = true }
    for lhs, data in pairs(editor_keymaps) do
        local func, desc = data[1], data[2]
        local handler = function()
            func()
            if desc then utils.info(desc) end
        end

        vim.keymap.set("n", lhs, handler, key_opts)
        local uk = utils.translate_key(lhs)
        if uk ~= lhs then vim.keymap.set("n", uk, handler, key_opts) end
    end

    vim.api.nvim_create_autocmd("WinEnter", {
        group = group,
        callback = function()
            if M.help_win and vim.api.nvim_win_is_valid(M.help_win) and vim.api.nvim_get_current_win() == M.help_win then
                if M.win and vim.api.nvim_win_is_valid(M.win) then
                    vim.api.nvim_set_current_win(M.win)
                end
            end
        end,
    })

    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = M.buf,
        group = group,
        callback = function() close_help_window() end,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
        buffer = M.buf,
        group = group,
        callback = function()
            M.win = vim.api.nvim_get_current_win()
            setup_help_window()
        end,
    })

    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = M.buf,
        group = group,
        callback = function()
            close_help_window()
            state.set_mode("NORMAL")

            if not state.is_changed then
                local src = state.get_source_buffer()
                if src and vim.api.nvim_buf_is_valid(src) then
                    vim.bo[src].modified = false
                end
            end

            pcall(vim.api.nvim_del_augroup_by_id, group)
        end,
    })
end

function M.refresh_editor_buffer()
    if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end
    local record = state.current_record()
    local field = state.field_name()
    local content_lines = vim.deepcopy(record[field] or {})

    local cursor = vim.api.nvim_win_get_cursor(M.win)
    vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, content_lines)

    local max_line = #content_lines
    if cursor[1] > max_line then cursor[1] = max_line end
    if cursor[1] < 1 then cursor[1] = 1 end
    pcall(vim.api.nvim_win_set_cursor, M.win, cursor)

    vim.bo[M.buf].modified = false
    update_buffer_title()
end

function M.save_core(silent_write)
    if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end

    local record = state.current_record()
    local field = state.field_name()

    local clean_lines = vim.api.nvim_buf_get_lines(M.buf, 0, -1, false)

    while #clean_lines > 0 and vim.trim(clean_lines[#clean_lines]) == "" do
        table.remove(clean_lines)
    end

    record[field] = clean_lines

    vim.bo[M.buf].modified = false

    update_buffer_title()
    vim.cmd("redrawstatus")

    local src = state.get_source_buffer()
    if src and vim.api.nvim_buf_is_valid(src) then
        local file_path = vim.api.nvim_buf_get_name(src)

        state.sync_to_disk()

        vim.api.nvim_buf_call(src, function()
            if file_path and file_path ~= "" then
                pcall(vim.cmd, "silent write! " .. vim.fn.fnameescape(file_path))
            end
            vim.bo[src].modified = false
        end)
    end
end

function M.render_status()
    if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return "" end

    local modified = vim.bo[M.buf].modified and " [+] " or " "

    local prev_hint = get_prev_field_preview()
    if prev_hint ~= "" then prev_hint = " │" .. prev_hint end

    return string.format(
        " РЕДАКТУВАННЯ: Картка %d/%d, поле: %s%s%s │ :w - зберегти │ :q - вийти",
        state.index(), state.count(), state.field_name(), modified, prev_hint
    )
end

function M.render_help_status()
    local stats = get_text_stats()
    local left = string.format(" 📊 Символів: %d  │  Слів: %d  │  Рядків: %d", stats.chars, stats.words, stats.lines)
    local right = " * "

    local width = 80
    if M.help_win and vim.api.nvim_win_is_valid(M.help_win) then
        width = vim.api.nvim_win_get_width(M.help_win)
    end

    local padding = width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right)
    if padding < 1 then padding = 1 end

    return left .. string.rep(" ", padding) .. right
end

return M
