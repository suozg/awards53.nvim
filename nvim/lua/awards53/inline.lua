-- lua/awards53/ui/inline.lua
local M = {}

local state = require("awards53.state")
local utils = require("awards53.utils")
local serializer = require("awards53.serializer")
local actions = require("awards53.actions")

M.inline_ns = vim.api.nvim_create_namespace("awards53_inline_edit")

M.edit_state = {
    active = false,
    card_idx = nil,
    field = nil,
    start_row = nil,
    end_mark = nil,
    indent = "    ",
    original_lines = nil,
}

local function keep_cursor_inside_inline_field(ui_state)
    if not M.edit_state.active then
        return
    end

    local win = ui_state.body_win
    if not win or not vim.api.nvim_win_is_valid(win) then
        return
    end

    local buf = ui_state.body_buf
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    if not M.edit_state.end_mark then
        return
    end

    local mark_pos = vim.api.nvim_buf_get_extmark_by_id(
        buf,
        M.inline_ns,
        M.edit_state.end_mark,
        {}
    )

    if not mark_pos or not mark_pos[1] then
        return
    end

    local min_row = M.edit_state.start_row or 0
    local max_row = math.max(min_row, mark_pos[1] - 1)

    local cursor = vim.api.nvim_win_get_cursor(win)
    local row = math.min(math.max(cursor[1] - 1, min_row), max_row)

    if row ~= cursor[1] - 1 then
        vim.api.nvim_win_set_cursor(win, { row + 1, cursor[2] })
    end
end

local function set_inline_keymaps(ui_state, redraw_cb)
    local opts = {
        buffer = ui_state.body_buf,
        silent = true,
        nowait = true,
        noremap = true,
    }

    local group = vim.api.nvim_create_augroup("Awards53InlineCursorLock", { clear = true })

    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = group,
        buffer = ui_state.body_buf,
        callback = function()
            keep_cursor_inside_inline_field(ui_state)
        end,
    })

    vim.keymap.set("i", "<Esc>", function()
        vim.cmd("stopinsert")
        M.commit(ui_state, redraw_cb)
    end, opts)

    vim.keymap.set({ "i", "n" }, "<C-c>", function()
        vim.cmd("stopinsert")
        M.cancel(ui_state, redraw_cb)
    end, opts)

    local n_actions = {
        ["R"] = actions.action_R,
        ["X"] = actions.action_X,
        ["T"] = actions.action_S,
        ["C"] = actions.action_E,
    }

    for key, fn in pairs(n_actions) do
        vim.keymap.set("n", key, function()
            vim.cmd("stopinsert")
            fn()
        end, opts)
    end
end

local function clear_inline_field_highlights(buf, start_row, end_row)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    if start_row == nil or end_row == nil then
        return
    end

    local cfg = require("awards53")
    local NS_ID = cfg.ns_fields or vim.api.nvim_create_namespace("awards53_fields")

    vim.api.nvim_buf_clear_namespace(
        buf,
        NS_ID,
        start_row,
        end_row + 1
    )
end

-- clear_inline_keymaps: удаляем те же клавиши, что ставим в set_inline_keymaps
local function clear_inline_keymaps(buf)
    pcall(vim.api.nvim_del_augroup_by_name, "Awards53InlineCursorLock")

    if buf and vim.api.nvim_buf_is_valid(buf) then
        -- удаляем только те маппинги, которые создаём
        pcall(vim.keymap.del, "i", "<Esc>", { buffer = buf })
        pcall(vim.keymap.del, "i", "<C-c>", { buffer = buf })
        pcall(vim.keymap.del, "n", "<C-c>", { buffer = buf })
        -- нормальные экшн-клавиши, которые устанавливали: R, X, T, C
        for _, key in ipairs({ "R", "X", "T", "C" }) do
            pcall(vim.keymap.del, "n", key, { buffer = buf })
        end
    end
end

function M.cleanup(ui_state)
    -- если буфер валиден — убедимся, что он снова не модифицируемый
    if ui_state and ui_state.body_buf and vim.api.nvim_buf_is_valid(ui_state.body_buf) then
        pcall(vim.api.nvim_buf_set_option, ui_state.body_buf, "modifiable", false)
        -- удаляем extmark (если есть)
        pcall(
            vim.api.nvim_buf_del_extmark,
            ui_state.body_buf,
            M.inline_ns,
            M.edit_state.end_mark
        )
    end

    clear_inline_keymaps(ui_state and ui_state.body_buf or nil)

    M.edit_state = {
        active = false,
        card_idx = nil,
        field = nil,
        start_row = nil,
        end_mark = nil,
        indent = "    ",
        original_lines = nil,
    }
end

function M.start(ui_state, redraw_cb)
    if M.edit_state.active then
        return
    end

    local buf = ui_state.body_buf
    local win = ui_state.body_win

    if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
    if not (win and vim.api.nvim_win_is_valid(win)) then return end

    local card_idx = state.index()
    local field = state.field_name()
    local range = ui_state.current_ranges and ui_state.current_ranges[field]

    if not range then
        utils.warn("Не вдалося визначити межі поля для inline-редагування")
        return
    end

    clear_inline_field_highlights(buf, range.start_row, range.end_row)

    local raw_lines = vim.api.nvim_buf_get_lines(
        buf,
        range.start_row,
        range.end_row + 1,
        false
    )
    local stripped_lines = {}

    for _, line in ipairs(raw_lines) do
        table.insert(stripped_lines, (line:gsub("^" .. range.indent, "", 1)))
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, range.start_row, range.end_row + 1, false, stripped_lines)

    local line_count = vim.api.nvim_buf_line_count(buf)
    local boundary_row = math.min(range.end_row + 1, math.max(0, line_count - 1))

    local end_mark = vim.api.nvim_buf_set_extmark(
        buf,
        M.inline_ns,
        boundary_row,
        0,
        {
            right_gravity = false,
            invalidate = false,
        }
    )

    M.edit_state = {
        active = true,
        card_idx = card_idx,
        field = field,
        start_row = range.start_row,
        end_mark = end_mark,
        indent = range.indent,
        original_lines = vim.deepcopy(raw_lines),
    }

    set_inline_keymaps(ui_state, redraw_cb)

    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, { range.start_row + 1, 0 })

    state.set_mode("INSERT")
    vim.cmd("startinsert!")
end

function M.commit(ui_state, redraw_cb)
    if not M.edit_state.active then
        return
    end

    local buf = ui_state.body_buf
    if not (buf and vim.api.nvim_buf_is_valid(buf)) then
        M.cleanup(ui_state)
        return
    end

    -- визначаємо межі inline-блоку
    local mark_pos = vim.api.nvim_buf_get_extmark_by_id(buf, M.inline_ns, M.edit_state.end_mark, {})
    local start_row = M.edit_state.start_row
    local end_row = mark_pos and mark_pos[1] and (mark_pos[1] - 1) or start_row

    -- зчитуємо редаговані рядки (але НЕ пишемо їх у state поки не перевірили)
    local edited_lines = vim.api.nvim_buf_get_lines(buf, start_row, end_row + 1, false)

    -- перевіряємо, чи є джерельний .org-буфер і чи він незбережений
    local src_buf = state.get_source_buffer()
    if src_buf and vim.api.nvim_buf_is_valid(src_buf) then
        local ok, src_modified = pcall(vim.api.nvim_buf_get_option, src_buf, "modified")
        if not ok then src_modified = false end

        if src_modified then
            -- Блокуємо збереження тут — просимо спочатку зберегти .org-файл
            utils.warn("Спочатку збережіть вихідний .org-файл, потім збережіть картку.")
            -- відміняємо inline-редагування (відновлюємо original_lines)
            M.cancel(ui_state, redraw_cb)
            return
        end
    end

    -- якщо ми сюди дійшли — src чистий або його немає -> застосовуємо зміни у state і записуємо
    local rec = state.records[M.edit_state.card_idx]
    if rec then
        state.snapshot()

        local field_key = tostring(M.edit_state.field)
        rec[field_key] = edited_lines

        -- якщо є src_buf — формуємо повний текст і перезаписуємо блок Awards53
        if src_buf and vim.api.nvim_buf_is_valid(src_buf) then
            local full_lines = serializer.build({
                headers = state.headers,
                records = state.records,
            })

            local first_line = vim.api.nvim_buf_get_lines(src_buf, 0, 1, false)[1] or ""
            local ok_set, err = pcall(function()
                if first_line:match("^%*%s+AWARDS53") then
                    vim.api.nvim_buf_set_lines(src_buf, 1, -1, false, full_lines)
                else
                    vim.api.nvim_buf_set_lines(src_buf, 0, -1, false, full_lines)
                end
            end)

            if not ok_set then
                utils.error("Помилка підготовки запису: " .. tostring(err))
            else
                -- записуємо файл (використовуємо pcall на випадок помилки)
                pcall(vim.api.nvim_buf_call, src_buf, function()
                    pcall(vim.cmd, "silent! write!")
                end)
            end
        end

        -- відмічаємо як збережено
        state.mark_as_clean()
    end

    -- завершити inline
    M.cleanup(ui_state)
    state.set_mode("NORMAL")
    if redraw_cb then redraw_cb() end
end

function M.cancel(ui_state, redraw_cb)
    if not M.edit_state.active then
        return
    end

    local buf = ui_state.body_buf

    -- Відновлюємо початкові рядки, якщо скасовуємо редагування через <C-c>
    if buf and vim.api.nvim_buf_is_valid(buf) and M.edit_state.original_lines then
        local mark_pos = vim.api.nvim_buf_get_extmark_by_id(
            buf,
            M.inline_ns,
            M.edit_state.end_mark,
            {}
        )
        local start_row = M.edit_state.start_row
        local end_row = mark_pos and mark_pos[1] and (mark_pos[1] - 1) or start_row

        -- сделаем модификабельным, запишем и снова запретим редактирование
        pcall(vim.api.nvim_buf_set_option, buf, "modifiable", true)
        pcall(vim.api.nvim_buf_set_lines, buf, start_row, end_row + 1, false, M.edit_state.original_lines)
        pcall(vim.api.nvim_buf_set_option, buf, "modifiable", false)
    end

    M.cleanup(ui_state)
    state.set_mode("NORMAL")

    if redraw_cb then
        redraw_cb()
    end
end

return M
