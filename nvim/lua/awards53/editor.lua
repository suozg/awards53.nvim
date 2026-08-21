local M = {}

local state = require("awards53.state")
local utils = require("awards53.utils")
local actions = require("awards53.actions")
local search_module = require("awards53.searchtxt")

M.help_buf = nil -- Буфер підказок
M.help_win = nil -- Вікно підказок внизу

local help_lines = {
    "  R / X - Форматувати посаду у цьому полі / ПО ВСІХ КАРТКАХ   |  e / Е  - Склеїти рядки поточного поля / у ВСІХ картках",
    "  f / a - Шукати фразу в ~/STATISTIKA / в базі нагород awards |  c      - Скинути пошуковий пароль ",
}

-- -----------------------------------------------------------------------------
-- ДОПОМІЖНІ ФУНКЦІЇ
-- -----------------------------------------------------------------------------
local function get_text_stats(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return { lines = 0, words = 0, chars = 0 }
    end

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local line_count = #lines
    local word_count = 0
    local char_count = 0

    for _, line in ipairs(lines) do
        char_count = char_count + vim.fn.strchars(line)
        for _ in string.gmatch(line, "%S+") do
            word_count = word_count + 1
        end
    end

    return { lines = line_count, words = word_count, chars = char_count }
end


local function setup_help_window()
    if M.help_win and vim.api.nvim_win_is_valid(M.help_win) then return end

    vim.schedule(function()
        if M.help_win and vim.api.nvim_win_is_valid(M.help_win) then return end

        if not (M.help_buf and vim.api.nvim_buf_is_valid(M.help_buf)) then
            M.help_buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(M.help_buf, 0, -1, false, help_lines)
            local h_bo = vim.bo[M.help_buf]
            h_bo.buftype, h_bo.bufhidden, h_bo.swapfile, h_bo.modifiable = "nofile", "hide", false, false
        end

        local ok, win = pcall(vim.api.nvim_open_win, M.help_buf, false, {
            split = "below",
            height = #help_lines,
            win = -1,
        })

        if not ok or not win or not vim.api.nvim_win_is_valid(win) then
            return
        end

        M.help_win = win

        local h_wo = vim.wo[M.help_win]
        h_wo.number, h_wo.relativenumber, h_wo.signcolumn, h_wo.colorcolumn, h_wo.spell = false, false, "no", "", false
        h_wo.winfixheight = true
        h_wo.statusline = "%!v:lua.require'awards53.editor'.render_help_status()"
        h_wo.winhighlight = "Normal:Awards53Help,NormalNC:Awards53Help,SignColumn:Awards53Help"

        local cfg = require("awards53")
        local ns = cfg.ns_help or vim.api.nvim_create_namespace("awards53_editor_help")
        for i = 0, #help_lines - 1 do
            vim.api.nvim_buf_add_highlight(M.help_buf, ns, "Awards53HelpText", i, 0, -1)
        end
    end)
end

local function close_help_window()
    if M.help_win and vim.api.nvim_win_is_valid(M.help_win) then
        pcall(vim.api.nvim_win_close, M.help_win, true)
        M.help_win = nil
    end
end

local function get_prev_field_preview(card_idx, field_idx)
    local records = state.records
    local record = records[card_idx]
    if not record then return "" end

    if not field_idx or field_idx <= 1 then return "" end

    local headers = state.headers_list()
    local first_field_name = headers[1]
    if not first_field_name then return "" end

    local first_field_data = record[first_field_name]

    if first_field_data and #first_field_data > 0 then
        local first_line = vim.trim(first_field_data[1] or "")
        if first_line ~= "" then
            if vim.fn.strchars(first_line) > 20 then
                first_line = vim.fn.strcharpart(first_line, 0, 30) .. "…"
            end
            return string.format(" 👈: %s", first_line)
        end
    end

    return ""
end

local function get_editor_context_name(card_idx, field_name)
    local record = state.records[card_idx]
    if not record then return "потоку" end

    local first_field_text = ""
    local headers = state.headers_list()
    local first_field_name = headers[1]

    if first_field_name and record[first_field_name] and #record[first_field_name] > 0 then
        first_field_text = vim.trim(record[first_field_name][1] or "")
        if first_field_text ~= "" and vim.fn.strchars(first_field_text) > 20 then
            first_field_text = vim.fn.strcharpart(first_field_text, 0, 20) .. "…"
        end
    end

    if first_field_text ~= "" then
        return string.format("полі '%s' картки '%s'", field_name, first_field_text)
    else
        return string.format("полі '%s' картки №%d", field_name, card_idx)
    end
end

local function update_buffer_title(buf, card_idx, field_name)
    if not buf or type(buf) ~= "number" or not vim.api.nvim_buf_is_valid(buf) then return end

    local record = state.records[card_idx]
    if not record then return end

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
        base_title = string.format("%s (поле %s)", first_field_text, field_name)
    else
        base_title = string.format("Картка %d (поле %s)", card_idx, field_name)
    end

    local is_modified = vim.bo[buf].modified
    local prefix = is_modified and "* " or ""
    local buf_title = prefix .. base_title

    pcall(vim.api.nvim_buf_set_name, buf, buf_title)
end

-- -----------------------------------------------------------------------------
-- ГОЛОВНА ФУНКЦІЯ ВІДКРИТТЯ РЕДАКТОРА
-- -----------------------------------------------------------------------------

function M.open()
    local record = state.current_record()
    local field = state.field_name()
    local card_idx = state.index()
    local field_idx = state.field_index()

    local key = string.format("%d:%s", card_idx, field)

    local existing_buf = state.opened_editors[key]
    if existing_buf and vim.api.nvim_buf_is_valid(existing_buf) then
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == existing_buf then
                vim.api.nvim_set_current_win(win)
                utils.info("Переключено фокус на вже відкритий буфер поля")
                return
            end
        end

        vim.api.nvim_win_set_buf(0, existing_buf)
        setup_help_window()
        return
    end

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(0, buf)
    local win = vim.api.nvim_get_current_win()

    vim.b[buf].card_idx = card_idx
    vim.b[buf].field_name = field
    vim.b[buf].field_idx = field_idx

    state.opened_editors[key] = buf

    local bo = vim.bo[buf]
    bo.bufhidden, bo.swapfile, bo.filetype, bo.spelllang = "hide", false, "org", "uk,en"
    bo.buftype = "acwrite"

    local content_lines = vim.deepcopy(record[field] or {})
    if #content_lines == 0 then content_lines = { "" } end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content_lines)
    require("awards53.abbreviations").register_buffer_abbreviations(buf)

    utils.highlight_rnokpp_in_buf(buf)
    bo.modified = false

    update_buffer_title(buf, card_idx, field)

    vim.api.nvim_win_set_cursor(win, { 1, 0 })

    local wo = vim.wo[win]
    wo.spell, wo.statusline = true, "%!v:lua.require'awards53.editor'.render_status()"

    setup_help_window()

    local group = vim.api.nvim_create_augroup("Awards53Editor_" .. buf, { clear = true })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = buf, 
        group = group, 
        callback = function() 
            update_buffer_title(buf, card_idx, field)
            vim.cmd("redrawstatus!") 
        end,
    })

    local function save_and_notify()
        M.save_core(buf)
        utils.highlight_rnokpp_in_buf(buf)
        utils.info("Зміни збережено в org-файл!")
    end

    vim.api.nvim_create_autocmd("BufWriteCmd", { 
        buffer = buf, 
        group = group, 
        callback = save_and_notify 
    })
    
    vim.api.nvim_buf_create_user_command(buf, "W", save_and_notify, {})

    vim.api.nvim_buf_create_user_command(buf, "Q", function(opts)
        local target_buf = buf
        if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then return end

        local is_modified = vim.bo[target_buf].modified

        if is_modified and not opts.bang then
            local context_info = get_editor_context_name(card_idx, field)
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
        state.opened_editors[key] = nil

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
        ["R"] = { function() M.save_core(buf) actions.format_rnokpp_in_current_card() M.refresh_editor_buffer(buf) end, nil },
        ["X"] = { function() M.save_core(buf) actions.format_rnokpp_in_all_cards() M.refresh_editor_buffer(buf) end, nil },
        ["e"] = { function() M.save_core(buf) state.flatten_current_field() M.refresh_editor_buffer(buf) end, nil },
        ["E"] = { function() M.save_core(buf) state.flatten_field_globally() M.refresh_editor_buffer(buf) end, nil },
        ["f"] = { function() search_module.process_all_rnokpp() end, "Пошук в ~/STATISTIKA/shtat" }, 
        ["c"] = { function() search_module.clear_passwords() end, "Скидання пароля" }, 
        ["a"] = { function() search_module.run_sql_search() end, "Пошук по SQLCipher базі нагород" },
        ["?"] = { function() require("awards53.help").open() end, false }, 
    }

    local key_opts = { buffer = buf, silent = true, noremap = true }
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

    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = buf,
        group = group,
        callback = function() close_help_window() end,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
        buffer = buf,
        group = group,
        callback = function()
            setup_help_window()
        end,
    })

    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = buf,
group = group,
        callback = function()
            close_help_window()
            state.opened_editors[key] = nil
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

function M.refresh_editor_buffer(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

    local card_idx = vim.b[buf].card_idx
    local field = vim.b[buf].field_name
    if not card_idx or not field then return end

    local record = state.records[card_idx]
    if not record then return end

    local content_lines = vim.deepcopy(record[field] or {})

    local win = vim.fn.bufwinid(buf)
    local cursor = { 1, 0 }
    if win ~= -1 then
        cursor = vim.api.nvim_win_get_cursor(win)
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content_lines)

    local max_line = #content_lines
    if cursor[1] > max_line then cursor[1] = max_line end
    if cursor[1] < 1 then cursor[1] = 1 end

    if win ~= -1 then
        pcall(vim.api.nvim_win_set_cursor, win, cursor)
    end

    vim.bo[buf].modified = false
    update_buffer_title(buf, card_idx, field)
end

function M.save_core(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

    local card_idx = vim.b[buf].card_idx
    local field = vim.b[buf].field_name
    if not card_idx or not field then return end

    local record = state.records[card_idx]
    if not record then return end

    local clean_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    while #clean_lines > 0 and vim.trim(clean_lines[#clean_lines]) == "" do
        table.remove(clean_lines)
    end

    record[field] = clean_lines
    vim.bo[buf].modified = false

    update_buffer_title(buf, card_idx, field)
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
    local buf = vim.api.nvim_get_current_buf()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return "" end

    local card_idx = vim.b[buf].card_idx or state.index()
    local field = vim.b[buf].field_name or state.field_name()
    local field_idx = vim.b[buf].field_idx or state.field_index()

    local modified = vim.bo[buf].modified and " [+] " or " "

    local prev_hint = get_prev_field_preview(card_idx, field_idx)
    if prev_hint ~= "" then prev_hint = " │" .. prev_hint end

    return string.format(
        " РЕДАКТУВАННЯ: Картка %d/%d, поле: %s%s%s │ :w - зберегти │ :q - зберегти та вийти, або :q! - вийти без збереження ",
        card_idx, state.count(), field, modified, prev_hint
    )
end

function M.render_help_status()
    -- Знаходимо буфер активного редактора поля через поточне вікно або збережені редактори
    local current_buf = vim.api.nvim_get_current_buf()
    -- Якщо фокус у вікні редактора поля, беремо його, інакше шукаємо серед відкритих
    local stats = get_text_stats(current_buf)
    
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

function M.mark_as_saved(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.bo[buf].modified = false
        local card_idx = vim.b[buf].card_idx
        local field = vim.b[buf].field_name
        if card_idx and field then
            update_buffer_title(buf, card_idx, field)
        end
        vim.cmd("redrawstatus!")
    end
end

return M
