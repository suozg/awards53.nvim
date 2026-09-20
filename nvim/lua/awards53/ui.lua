-- ui.lua (Модуль користувацького інтерфейсу картки та вікон)

local M = {}

local header = require("awards53.header")
local body = require("awards53.body")
local state = require("awards53.state")
local editor = require("awards53.editor")
local utils = require("awards53.utils")
local actions = require("awards53.actions")
local move_karta = require("awards53.move_karta")
local mappings = require("awards53.mappings")

M.body_buf = nil
M.body_win = nil

M.current_ranges = {}
M.inline_ns = vim.api.nvim_create_namespace("awards53_inline_edit")

M.inline_edit = {
    active = false,
    card_idx = nil,
    field = nil,
    start_row = nil,
    end_mark = nil,
    indent = "    ",
    original_lines = nil,
}

local cfg = require("awards53")
local NS_ID = cfg.ns_fields or vim.api.nvim_create_namespace("awards53_fields")
local syntax_group = "Awards53ActiveField"

vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("Awards53HighlightsAutoRestore", { clear = true }),
    callback = function()
        if M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf) then
            M.redraw()
        end
    end,
})

local function apply_field_highlighting(buf)
    vim.api.nvim_buf_clear_namespace(buf, NS_ID, 0, -1)
    local line_count = vim.api.nvim_buf_line_count(buf)
    local in_block = false

    for i = 0, line_count - 1 do
        local line = vim.api.nvim_buf_get_lines(buf, i, i + 1, false)[1]

        local is_bracket_line = line and (line:find("^%s*%[") ~= nil)
        local is_dot_line = line and (line:match("^%s*%.") ~= nil)

        if is_bracket_line then
            in_block = true
        end

        if in_block and line then
            vim.api.nvim_buf_set_extmark(buf, NS_ID, i, 0, {
                end_row = i,
                end_col = #line,
                hl_group = "Awards53Separator",
                priority = 100,
            })
        end

        if is_dot_line then
            in_block = false
        end

        if line and line:match("󰓻") then
            local sep_len = #("")
            local first_sep = line:find("")
            local last_sep = nil

            if first_sep then
                last_sep = line:find("", first_sep + sep_len)
            end

            local end_col = last_sep and (last_sep - 1) or #line

            vim.api.nvim_buf_set_extmark(buf, NS_ID, i, 0, {
                end_row = i,
                end_col = end_col,
                hl_group = syntax_group,
                hl_eol = false,
                priority = 100,
            })

            if first_sep then
                vim.api.nvim_buf_set_extmark(buf, NS_ID, i, 0, {
                    end_row = i,
                    end_col = first_sep - 1,
                    hl_group = "Awards53ActiveFieldPrefix",
                    priority = 200,
                })

                vim.api.nvim_buf_set_extmark(buf, NS_ID, i, first_sep - 1, {
                    end_row = i,
                    end_col = first_sep - 1 + sep_len,
                    hl_group = "Awards53ActiveFieldSeparator",
                    priority = 200,
                })
            end

            if last_sep then
                vim.api.nvim_buf_set_extmark(buf, NS_ID, i, last_sep - 1, {
                    end_row = i,
                    end_col = last_sep - 1 + sep_len,
                    hl_group = "Awards53ActiveFieldSuffix",
                    priority = 200,
                })
            end
        end
    end
end

local function render_body()
    local lines = {}
    vim.list_extend(lines, header.render())
    vim.list_extend(lines, body.render())
    return lines
end

local function update_ui_buffer_title()
    if not (M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf)) then
        return
    end

    local src_buf = state.get_source_buffer()
    local is_modified = state.is_changed

    if src_buf and vim.api.nvim_buf_is_valid(src_buf) and vim.bo[src_buf].modified then
        is_modified = true
    end

    vim.bo[M.body_buf].modified = is_modified
    local title = is_modified and "[+] Awards53" or "Awards53"
    pcall(vim.api.nvim_buf_set_name, M.body_buf, title)
end

local function update_header_highlight()
    if state.is_changed then
        vim.cmd("highlight! link OrgCardHeader WarningMsg")
    else
        vim.cmd("highlight! link OrgCardHeader Title")
    end
end

local function render_body_with_ranges()
    local header_lines = header.render()
    local body_lines, ranges = body.render()

    local full_lines = {}
    vim.list_extend(full_lines, header_lines)
    vim.list_extend(full_lines, body_lines)

    local header_offset = #header_lines
    local adjusted_ranges = {}

    for f_name, r_data in pairs(ranges) do
        adjusted_ranges[f_name] = {
            start_row = r_data.start_row + header_offset,
            end_row = r_data.end_row + header_offset,
            indent = r_data.indent,
        }
    end

    return full_lines, adjusted_ranges
end

function M.redraw()
    if M.inline_edit and M.inline_edit.active then
        return
    end

    vim.bo.modified = state.is_changed
    update_header_highlight()

    if not (M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf)) then
        return
    end

    local current_win = vim.api.nvim_get_current_win()
    local current_buf = vim.api.nvim_win_get_buf(current_win)

    local is_editing_card_buffer = (M.body_win and vim.api.nvim_win_is_valid(M.body_win))
        and (current_win == M.body_win)
        and (current_buf == M.body_buf)

    local saved_cursor = nil
    if is_editing_card_buffer then
        saved_cursor = vim.api.nvim_win_get_cursor(M.body_win)
    end

    local full_lines, ranges = render_body_with_ranges()
    M.current_ranges = ranges

    vim.bo[M.body_buf].modifiable = true
    vim.api.nvim_buf_set_lines(M.body_buf, 0, -1, false, full_lines)
    vim.bo[M.body_buf].modifiable = false

    utils.highlight_rnokpp_in_buf(M.body_buf)
    apply_field_highlighting(M.body_buf)

    if is_editing_card_buffer and saved_cursor then
        local line_count = vim.api.nvim_buf_line_count(M.body_buf)
        if saved_cursor[1] > line_count then
            saved_cursor[1] = line_count
        end
        pcall(vim.api.nvim_win_set_cursor, M.body_win, saved_cursor)
    end

    update_ui_buffer_title()
    vim.cmd("redrawstatus!")
end


-- Вікно історії змін (Undotree) з Diff
function M.open_undotree_window()
    local entries = state.get_undo_list()

    if #entries == 0 then
        utils.info("Історія дій порожня")
        return
    end

    local list_lines = {}
    local seq_map = {}

    for idx, entry in ipairs(entries) do
        local mark = entry.is_current and "➔ " or "  "
        local line = string.format("%s[%d] %s", mark, entry.seq, entry.time)
        table.insert(list_lines, line)
        seq_map[idx] = entry.seq
    end

    local list_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, list_lines)

    local preview_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[preview_buf].filetype = "diff"

    local total_width = math.min(vim.o.columns - 6, 110)
    local list_width = 24
    local preview_width = total_width - list_width - 3
    local height = math.min(#list_lines + 4, 20)

    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - total_width) / 2)

    local list_win = vim.api.nvim_open_win(list_buf, true, {
        relative = "editor",
        width = list_width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Історія (U) ",
        title_pos = "center",
    })

    local preview_win = vim.api.nvim_open_win(preview_buf, false, {
        relative = "editor",
        width = preview_width,
        height = height,
        row = row,
        col = col + list_width + 2,
        style = "minimal",
        border = "rounded",
        title = " Різниця змін ",
        title_pos = "center",
    })

    vim.bo[list_buf].buftype = "nofile"
    vim.bo[list_buf].modifiable = false
    vim.bo[preview_buf].buftype = "nofile"

    local diff_ns = vim.api.nvim_create_namespace("Awards53UndoDiff")

    -- Фіксуємо стан документа на момент відкриття Undotree.
    -- Під час перегляду історії він не повинен змінюватися.
    local src_buf = state.get_source_buffer()

    if not src_buf or not vim.api.nvim_buf_is_valid(src_buf) then
        return
    end

    local base_lines = vim.api.nvim_buf_get_lines(src_buf, 0, -1, false)

    local base_tree = vim.api.nvim_buf_call(src_buf, function()
        return vim.fn.undotree()
    end)

    local base_seq = base_tree.seq_cur

    -- Кеш історичних станів.
    local target_cache = {}

    -- Кеш уже готового diff.
    local diff_cache = {}

    local function update_preview()
        if not vim.api.nvim_win_is_valid(list_win)
            or not vim.api.nvim_buf_is_valid(preview_buf) then
            return
        end

        local cursor = vim.api.nvim_win_get_cursor(list_win)
        local selected_seq = seq_map[cursor[1]]

        if not selected_seq then
            return
        end

        -- Якщо цей diff вже рахували — просто показуємо його.
        local diff_lines = diff_cache[selected_seq]

        if not diff_lines then
            local target_lines = target_cache[selected_seq]

            -- Поточний стан.
            if selected_seq == base_seq then
                target_lines = base_lines
            end

            -- Історичний стан ще не кешований.
            if not target_lines then
                local current_tree = vim.api.nvim_buf_call(src_buf, function()
                    return vim.fn.undotree()
                end)

                local current_seq = current_tree.seq_cur

                local ok, result = pcall(function()
                    vim.api.nvim_buf_call(src_buf, function()
                        vim.cmd("noautocmd silent undo " .. selected_seq)
                    end)

                    local lines = vim.api.nvim_buf_get_lines(
                        src_buf,
                        0,
                        -1,
                        false
                    )

                    -- Повертаємо документ у стан,
                    -- у якому він був до перегляду історії.
                    vim.api.nvim_buf_call(src_buf, function()
                        vim.cmd("noautocmd silent undo " .. current_seq)
                    end)

                    return lines
                end)

                if not ok then
                    return
                end

                target_lines = result
                target_cache[selected_seq] = target_lines
            end

            local current_text = table.concat(base_lines, "\n")
            local target_text = table.concat(target_lines, "\n")

            local diff_result = vim.diff(target_text, current_text, {
                algorithm = "myers",
                ctxlen = 3,
            })

            if diff_result == "" then
                diff_lines = {
                    "  (Змін немає / Поточний стан)"
                }
            else
                diff_lines = vim.split(diff_result, "\n", {
                    trimempty = true,
                })
            end

            diff_cache[selected_seq] = diff_lines
        end

        vim.bo[preview_buf].modifiable = true

        vim.api.nvim_buf_set_lines(
            preview_buf,
            0,
            -1,
            false,
            diff_lines
        )

        vim.bo[preview_buf].modifiable = false

        vim.api.nvim_buf_clear_namespace(
            preview_buf,
            diff_ns,
            0,
            -1
        )

        for i, line in ipairs(diff_lines) do
            local line_idx = i - 1

            if line:sub(1, 1) == "+"
                and not line:match("^%+%+%+") then

                vim.api.nvim_buf_set_extmark(
                    preview_buf,
                    diff_ns,
                    line_idx,
                    0,
                    {
                        end_row = line_idx,
                        end_col = #line,
                        hl_group = "DiffAdd",
                    }
                )

            elseif line:sub(1, 1) == "-"
                and not line:match("^%-%-%-") then

                vim.api.nvim_buf_set_extmark(
                    preview_buf,
                    diff_ns,
                    line_idx,
                    0,
                    {
                        end_row = line_idx,
                        end_col = #line,
                        hl_group = "DiffDelete",
                    }
                )

            elseif line:match("^@@") then

                vim.api.nvim_buf_set_extmark(
                    preview_buf,
                    diff_ns,
                    line_idx,
                    0,
                    {
                        end_row = line_idx,
                        end_col = #line,
                        hl_group = "DiffLine",
                    }
                )
            end
        end
    end

    local augroup = vim.api.nvim_create_augroup(
        "Awards53UndoDiffPreview",
        { clear = true }
    )

    vim.api.nvim_create_autocmd("CursorMoved", {
        group = augroup,
        buffer = list_buf,
        callback = update_preview,
    })

    update_preview()

    
    local close_windows = function()
        pcall(vim.api.nvim_del_augroup_by_name, "Awards53UndoDiffPreview")
        if list_win and vim.api.nvim_win_is_valid(list_win) then
            vim.api.nvim_win_close(list_win, true)
        end
        if preview_win and vim.api.nvim_win_is_valid(preview_win) then
            vim.api.nvim_win_close(preview_win, true)
        end
    end

    vim.keymap.set("n", "<CR>", function()
        local cursor = vim.api.nvim_win_get_cursor(list_win)
        local selected_seq = seq_map[cursor[1]]
        close_windows()

        if selected_seq then
            if state.restore_to_seq(selected_seq) then
                M.redraw()
            end
        end
    end, { buffer = list_buf, silent = true })

    vim.keymap.set("n", "q", close_windows, { buffer = list_buf, silent = true })
    vim.keymap.set("n", "<Esc>", close_windows, { buffer = list_buf, silent = true })
end

local function bind_keys()
    local keymaps = {
        ["h"]   = { function() return state.prev() end, true },
        ["l"]   = { function() return state.next() end, true },
        ["[["]  = { function() state.first() end, true },
        ["]]"]  = { function() state.last() end, true },
        ["<H>"] = { function() state.jump(5) end, true },
        ["<L>"] = { function() state.jump(-5) end, true },

        ["g"]   = { function()
            local total_records = state.count()
            if total_records == 0 then return end

            local count = vim.v.count
            if count > 0 then
                state.goto_record(count)
                M.redraw()
            else
                vim.ui.input({ prompt = "Номер картки для переходу (1-" .. total_records .. "): " }, function(input)
                    local num = tonumber(input)
                    if num then
                        state.goto_record(num)
                        M.redraw()
                    end
                end)
            end
        end, false },

        ["j"]   = { function() return state.next_field() end, true },
        ["k"]   = { function() return state.prev_field() end, true },

        ["f"]   = { function()
            local total = #state.headers_list()
            if total == 0 then return end

            local count = vim.v.count
            if count > 0 then
                state.field = math.max(1, math.min(count, total))
                state.last_field = state.field
                M.redraw()
            else
                vim.ui.input({ prompt = "Номер поля для переходу (1-" .. total .. "): " }, function(input)
                    local num = tonumber(input)
                    if num then
                        state.field = math.max(1, math.min(num, total))
                        state.last_field = state.field
                        M.redraw()
                    end
                end)
            end
        end, false },

        ["J"]   = { function() return state.move_field_content_down() end, true },
        ["K"]   = { function() return state.move_field_content_up() end, true },

        ["m"]   = { function() state.toggle_bookmark() end, true },
        ["]m"]  = { function() return state.next_bookmark() end, true },
        ["[m"]  = { function() return state.prev_bookmark() end, true },

        ["i"] = {
            function()
                M.start_inline_edit()
            end,
            false,
        },

        ["I"] = {
            function()
                state.set_mode("INSERT")
                editor.open()
            end,
            false,
        },
        
        ["A"]   = { function() state.new_record() M.redraw() state.set_mode("INSERT") M.redraw() editor.open() end, false },

        ["F"]   = { function() if state.new_field() then M.redraw() utils.info("Додано нове поле №" .. state.field_name()) end end, false },
        ["F-"]  = { function() if state.new_field("-") then M.redraw() utils.info("Додано нове поле №" .. state.field_name() .. " із '-'") end end, false },
        ["B"]   = { function()
            if state.delete_field() then
                state.sync_to_disk()
                M.redraw()
                utils.info("Поле видалено")
            else
                utils.error("Не вдалося видалити поле")
            end
        end, false },

        ["dd"]  = { function()
            state.copy_current()
            if state.delete_current() then
                utils.info("Картку вирізано")
            else
                utils.error("Не можна видалити останню картку")
            end
        end, true },

        ["yy"]  = { function() state.copy_current() utils.info("Картку скопійовано") end, false },
        ["p"]   = { function() return state.paste_after() end, true },

        ["u"]   = { function()
            if state.undo_last() then
                M.redraw()
            end
        end, false },

        ["<C-r>"] = { function()
            if state.redo_last() then
                M.redraw()
            end
        end, false },

        ["U"]   = { function() M.open_undotree_window() end, false },
        ["dp"]  = { function() move_karta.move_to_fork() end, true },

        ["/"]   = { function()
            vim.ui.input({ prompt = "Пошук " .. cfg.config.default_sort .. ": " }, function(t)
                if t and t ~= "" then
                    state.find(t, 1)
                    M.redraw()
                end
            end)
        end, false },

        ["g/"]  = { function()
            vim.ui.select(state.headers_list(), { prompt = "🔍 Шукати в полі:" }, function(f)
                if f then
                    vim.ui.input({ prompt = "Пошук (" .. f .. "): " }, function(t)
                        if t and t ~= "" then
                            state.find(t, 1, f)
                            M.redraw()
                        end
                    end)
                end
            end)
        end, false },

        ["n"]   = { function() return state.find_next() end, true },
        ["N"]   = { function() return state.find_next(-1) end, true },
        ["0"]   = { function() return state.collapse_empty_fields_globally() end, true },
        ["O"]   = { function() actions.sort_officers_first() state.first() end, true },
        ["S"]   = { function() state.sort_by(cfg.config.default_sort) state.first() end, true },
        ["?"]   = { function() require("awards53.help").open() end, false },
    }

    mappings.bind_buffer_keymaps(M.body_buf, keymaps, "n")
end

local function clear_inline_field_highlights(start_row, end_row)
    -- Удаляет все временные подсветки полей из inline-буфера.
    -- Используется перед входом в inline-режим;
    if not M.body_buf or not vim.api.nvim_buf_is_valid(M.body_buf) then
        return
    end

    if start_row == nil or end_row == nil then
        return
    end

    -- Очищаем только содержимое поля.
    -- Строка индикатора находится выше и не затрагивается.
    vim.api.nvim_buf_clear_namespace(
        M.body_buf,
        NS_ID,
        start_row,
        end_row + 1
    )
end

    
local function keep_cursor_inside_inline_field()
    -- функція забороняє курсору виходити за межі поля inline
    if not M.inline_edit.active then
        return
    end

    local win = M.body_win
    if not win or not vim.api.nvim_win_is_valid(win) then
        return
    end

    if not M.body_buf or not vim.api.nvim_buf_is_valid(M.body_buf) then
        return
    end

    if not M.inline_edit.end_mark then
        return
    end

    local mark_pos = vim.api.nvim_buf_get_extmark_by_id(
        M.body_buf,
        M.inline_ns,
        M.inline_edit.end_mark,
        {}
    )

    if not mark_pos or not mark_pos[1] then
        return
    end

    local min_row = M.inline_edit.start_row or 0
    local max_row = math.max(min_row, mark_pos[1] - 1)

    local cursor = vim.api.nvim_win_get_cursor(win)
    local row = math.min(math.max(cursor[1] - 1, min_row), max_row)

    if row ~= cursor[1] - 1 then
        vim.api.nvim_win_set_cursor(win, { row + 1, cursor[2] })
    end
end

local function set_inline_keymaps()
    -- Включает специальные клавиши и autocmd только 
    -- на время inline-редактирования.
    local opts = {
        buffer = M.body_buf,
        silent = true,
        nowait = true,
        noremap = true,
    }

    local group = vim.api.nvim_create_augroup("Awards53InlineCursorLock", { clear = true })

    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = group,
        buffer = M.body_buf,
        callback = function()
            keep_cursor_inside_inline_field()
        end,
    })

    vim.keymap.set("i", "<Esc>", function()
        vim.cmd("stopinsert")
        M.commit_inline_edit()
    end, opts)

    vim.keymap.set({ "i", "n" }, "<C-c>", function()
        vim.cmd("stopinsert")
        M.cancel_inline_edit()
    end, opts)
end

local function clear_inline_keymaps()
    -- Отключает всё, что было включено функцией set_inline_keymaps().

    pcall(vim.api.nvim_del_augroup_by_name, "Awards53InlineCursorLock")

    pcall(vim.keymap.del, "i", "<Esc>", { buffer = M.body_buf })
    pcall(vim.keymap.del, "n", "<Esc>", { buffer = M.body_buf })
    pcall(vim.keymap.del, "i", "<C-c>", { buffer = M.body_buf })
    pcall(vim.keymap.del, "n", "<C-c>", { buffer = M.body_buf })
end

function M.start_inline_edit()
    -- Запускает inline-редактирование.
    -- Проверяет, что inline-режим ещё не активен.
    -- Находит текущую карточку и поле.
    -- Получает границы поля.
    -- Убирает старые подсветки.
    -- Убирает служебные отступы из текста.
    -- Делает буфер временно изменяемым.
    -- Создаёт end_mark, который отмечает конец поля.
    -- Сохраняет состояние в M.inline_edit.
    -- Включает ограничения курсора и специальные клавиши.
    -- Ставит курсор в начало поля.
    -- Переходит в Insert mode.

    if M.inline_edit.active then
        return
    end

    if not (M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf)) then
        return
    end

    local win = M.body_win
    if not win or not vim.api.nvim_win_is_valid(win) then
        return
    end

    local card_idx = state.index()
    local field = state.field_name()
    local range = M.current_ranges[field]

    if not range then
        utils.warn("Не вдалося визначити межі поля для inline-редагування")
        return
    end

    clear_inline_field_highlights(
        range.start_row,
        range.end_row
    )

    local raw_lines = vim.api.nvim_buf_get_lines(
        M.body_buf, 
        range.start_row,
        range.end_row + 1,
        false
    )
    local stripped_lines = {}

    for _, line in ipairs(raw_lines) do
        table.insert(stripped_lines, (line:gsub("^" .. range.indent, "", 1)))
    end

    vim.bo[M.body_buf].modifiable = true
    vim.api.nvim_buf_set_lines(M.body_buf, range.start_row, range.end_row + 1, false, stripped_lines)

    local line_count = vim.api.nvim_buf_line_count(M.body_buf)
    local boundary_row = math.min(range.end_row + 1, math.max(0, line_count - 1))

    local end_mark = vim.api.nvim_buf_set_extmark(
        M.body_buf,
        M.inline_ns,
        boundary_row,
        0,
        {
            right_gravity = false,
            invalidate = false,
        }
    )

    M.inline_edit = {
        active = true,
        card_idx = card_idx,
        field = field,
        start_row = range.start_row,
        end_mark = end_mark,
        indent = range.indent,
        original_lines = vim.deepcopy(raw_lines),
    }

    set_inline_keymaps()

    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, { range.start_row + 1, 0 })

    state.set_mode("INSERT")
    vim.cmd("startinsert!")
end


function M.commit_inline_edit()
    -- Сохраняет результат inline-редактирования.
    -- Проверяет, что inline-режим активен.
    -- Находит конец изменяемого поля через end_mark.
    -- Получает новые строки поля.
    -- Удаляет пустые строки в конце.
    -- Записывает результат в state.records.
    -- Создаёт снимок для undo.
    -- Завершает inline-режим.
    -- Отключает временные mapping-и.
    -- Синхронизирует данные с диском/исходным буфером.
    -- Очищает старые подсветки.
    -- Вызывает M.redraw(), чтобы заново правильно отрисовать поле.
    -- Вызывается клавишей <Esc>.
    
    if not M.inline_edit.active then
        return
    end

    local card_idx = M.inline_edit.card_idx
    local field = M.inline_edit.field
    local start_row = M.inline_edit.start_row

    local mark_pos = vim.api.nvim_buf_get_extmark_by_id(
        M.body_buf,
        M.inline_ns,
        M.inline_edit.end_mark,
        {}
    )

    if not mark_pos or not mark_pos[1] then
        local original_lines = M.inline_edit.original_lines
        local original_start = M.inline_edit.start_row

        if original_lines and original_start then
            vim.bo[M.body_buf].modifiable = true
            vim.api.nvim_buf_set_lines(
                M.body_buf,
                original_start,
                original_start + #original_lines,
                false,
                original_lines
            )
        end

        M.inline_edit.active = false
        vim.bo[M.body_buf].modifiable = false
        M.cleanup_inline_state()
        state.set_mode("NORMAL")
        M.redraw()
        utils.warn("Не вдалося визначити кінець inline-поля")
        return
    end

    local end_row = mark_pos[1]
    local edited_lines = vim.api.nvim_buf_get_lines(
        M.body_buf,
        start_row,
        end_row,
        false
    )

    while #edited_lines > 0 and vim.trim(edited_lines[#edited_lines]) == "" do
        table.remove(edited_lines)
    end

    if #edited_lines == 0 then
        edited_lines = { "" }
    end

    local record = state.records[card_idx]
    if not record then
        M.inline_edit.active = false
        vim.bo[M.body_buf].modifiable = false
        M.cleanup_inline_state()
        state.set_mode("NORMAL")
        M.redraw()
        utils.warn("Картка для inline-редагування більше не існує")
        return
    end

    state.snapshot()
    record[field] = edited_lines

    M.inline_edit.active = false
    vim.bo[M.body_buf].modifiable = false

    M.cleanup_inline_state()

    state.set_mode("NORMAL")
    local synced = state.sync_to_disk()

    M.redraw()

    if synced then
        utils.info(string.format(
            "Поле '%s' оновлено в редакторі. Для запису на диск натисніть :w",
            field
        ))
    else
        utils.warn(string.format(
            "Поле '%s' змінено, але синхронізація з вихідним буфером не вдалася",
            field
        ))
    end
end

function M.cancel_inline_edit()
    -- Он похож на commit_inline_edit(), но не сохраняет изменения.
    -- При нажатии <C-c> он:
    -- Завершает inline-режим.
    -- Отключает временные mapping-и.
    -- Очищает подсветку.
    -- Вызывает M.redraw().
    -- Возвращает исходное состояние данных.
    if not M.inline_edit.active then
        return
    end

    M.inline_edit.active = false
    vim.bo[M.body_buf].modifiable = false

    M.cleanup_inline_state()

    state.set_mode("NORMAL")
    M.redraw()

    utils.info("Зміни inline-поля скасовано")
end
    
function M.cleanup_inline_state()
    if M.inline_edit.end_mark then
        pcall(
            vim.api.nvim_buf_del_extmark,
            M.body_buf,
            M.inline_ns,
            M.inline_edit.end_mark
        )

        M.inline_edit.end_mark = nil
    end

    clear_inline_keymaps()

    M.inline_edit.card_idx = nil
    M.inline_edit.field = nil
    M.inline_edit.start_row = nil
    M.inline_edit.indent = "    "
    M.inline_edit.original_lines = nil
end

function M.open()
    if M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf)
       and M.body_win and vim.api.nvim_win_is_valid(M.body_win) then
        vim.api.nvim_set_current_win(M.body_win)
        M.redraw()
        return
    end

    if not (M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf)) then
        M.body_buf = vim.api.nvim_create_buf(true, false)

        vim.bo[M.body_buf].buftype = "acwrite"
        vim.bo[M.body_buf].bufhidden = "hide"
        vim.bo[M.body_buf].swapfile = false

        update_ui_buffer_title()

        -- обробка виду курсору - щоб він був в inline і зникав при виході
        local orig_guicursor = vim.o.guicursor
        local cursor_grp = vim.api.nvim_create_augroup("Awards53HiddenCursorToggle", { clear = true })

        vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
            buffer = M.body_buf,
            group = cursor_grp,
            callback = function()
                vim.o.guicursor = "n-v-c:block-Awards53HiddenCursor,i:ver25"
            end,
        })

        vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
            buffer = M.body_buf,
            group = cursor_grp,
            callback = function()
                vim.o.guicursor = orig_guicursor
            end,
        })

        local keys_to_disable = {
            "<Up>", "<Down>", "<Left>", "<Right>",
            "w", "b", "ge", "$", "^", "gg", "G"
        }
        for _, key in ipairs(keys_to_disable) do
            vim.keymap.set("n", key, "<Nop>", { buffer = M.body_buf, noremap = true, silent = true })
        end

        bind_keys()

        local function save_card_action()
            local commands = require("awards53.commands")
            commands.save_cards()
            M.redraw()
        end

        vim.api.nvim_create_autocmd("BufWriteCmd", {
            buffer = M.body_buf,
            callback = save_card_action,
        })

        vim.api.nvim_buf_create_user_command(M.body_buf, "W", save_card_action, { desc = "Зберегти картки" })

        vim.api.nvim_buf_create_user_command(M.body_buf, "Q", function(opts)
            if M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf) then
                vim.bo[M.body_buf].modified = false
            end

            if opts.bang then
                for _, b in ipairs(vim.api.nvim_list_bufs()) do
                    if vim.api.nvim_buf_is_valid(b) then
                        vim.bo[b].modified = false
                    end
                end
            end

            local target_win, target_buf = M.body_win, M.body_buf
            M.body_win, M.body_buf = nil, nil

            if target_win and vim.api.nvim_win_is_valid(target_win) then
                pcall(vim.api.nvim_win_close, target_win, true)
            elseif target_buf and vim.api.nvim_buf_is_valid(target_buf) then
                pcall(vim.api.nvim_buf_delete, target_buf, { force = true })
            end
        end, { bang = true })

        vim.cmd([[
            cnoreabbrev <buffer> <expr> q (getcmdtype() == ':' && bufnr('%') == ]] .. M.body_buf .. [[) ? 'Q' : 'q'
            cnoreabbrev <buffer> <expr> q! (getcmdtype() == ':' && bufnr('%') == ]] .. M.body_buf .. [[) ? 'Q!' : 'q!'
            cnoreabbrev <buffer> <expr> й (getcmdtype() == ':' && bufnr('%') == ]] .. M.body_buf .. [[) ? 'Q' : 'й'
            cnoreabbrev <buffer> <expr> й! (getcmdtype() == ':' && bufnr('%') == ]] .. M.body_buf .. [[) ? 'Q!' : 'й!'
            cnoreabbrev <buffer> <expr> w (getcmdtype() == ':' && bufnr('%') == ]] .. M.body_buf .. [[) ? 'W' : 'w'
            cnoreabbrev <buffer> <expr> w! (getcmdtype() == ':' && bufnr('%') == ]] .. M.body_buf .. [[) ? 'W' : 'w!'
            cnoreabbrev <buffer> <expr> ц (getcmdtype() == ':' && bufnr('%') == ]] .. M.body_buf .. [[) ? 'W' : 'ц'
            cnoreabbrev <buffer> <expr> ц! (getcmdtype() == ':' && bufnr('%') == ]] .. M.body_buf .. [[) ? 'W' : 'ц!'
        ]])

        local src_buf = state.get_source_buffer()
        if src_buf and vim.api.nvim_buf_is_valid(src_buf) then
            local group = vim.api.nvim_create_augroup("Awards53SourceSync", { clear = true })
            vim.api.nvim_create_autocmd({ "BufWritePost" }, {
                buffer = src_buf,
                group = group,
                callback = function()
                    local lines = vim.api.nvim_buf_get_lines(src_buf, 0, -1, false)
                    local parser_mod = require("awards53.parser")
                    local commands = require("awards53.commands")

                    local first, last = commands.find_awards_block(lines)
                    if first then
                        local block = vim.list_slice(lines, first + 1, last)
                        local data = parser_mod.parse(block)

                        local curr_rec = state.index()
                        local curr_fld = state.field_index()
                        state.set(data)
                        state.goto_record(curr_rec)
                        state.field = curr_fld

                        state.mark_as_clean()

                        if M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf) then
                            M.redraw()
                        end
                    end
                end,
            })
        end
        
        vim.api.nvim_create_autocmd("BufWipeout", {
            buffer = M.body_buf,
            callback = function()
                if state.is_changed then
                    local commands = require("awards53.commands")
                    commands.sync_org_buffer()
                end

                local src_buf = state.get_source_buffer()
                if src_buf and vim.api.nvim_buf_is_valid(src_buf) then
                    local src_path = vim.api.nvim_buf_get_name(src_buf)
                    require("awards53").release_lock(src_path)
                end

                state.set_source_buffer(nil)
                state.set_source_win(nil)

                M.body_buf, M.body_win = nil, nil
            end,
        })
    end

    M.body_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.body_win, M.body_buf)
    vim.wo[M.body_win].statusline = "%!v:lua.require'awards53.status'.render()"

    local wo = vim.wo[M.body_win]
    wo.number = false
    wo.relativenumber = false
    wo.signcolumn = "no"
    wo.colorcolumn = ""
    wo.cursorline = false
    wo.wrap = true
    wo.linebreak = true
    
    M.redraw()
end

function M.focus()
    if M.body_win and vim.api.nvim_win_is_valid(M.body_win) then
        vim.api.nvim_set_current_win(M.body_win)
    end
end

function M.close_editor()
    state.set_mode("NORMAL")
    M.redraw()
end

return M
