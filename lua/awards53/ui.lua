local M = {}

local header = require("awards53.header")
local body = require("awards53.body")
local status = require("awards53.status")
local state = require("awards53.state")
local editor = require("awards53.editor")

M.buf = nil
M.win = nil

---------------------------------------------------------

local function render()

    local lines = {}

    vim.list_extend(lines, header.render())
    vim.list_extend(lines, body.render())
    vim.list_extend(lines, status.render())

    return lines

end

---------------------------------------------------------

function M.redraw()

    if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
        return
    end

    vim.bo[M.buf].modifiable = true

    vim.api.nvim_buf_set_lines(
        M.buf,
        0,
        -1,
        false,
        render()
    )

    vim.bo[M.buf].modifiable = false

end

---------------------------------------------------------

local function map(lhs, rhs)

    vim.keymap.set(
        "n",
        lhs,
        rhs,
        { buffer = M.buf, silent = true }
    )

end

---------------------------------------------------------

local function bind_keys()

    map("h", function()

        if state.prev() then
            M.redraw()
        end

    end)

    map("l", function()

        if state.next() then
            M.redraw()
        end

    end)

    map("[[", function()

        state.first()
        M.redraw()

    end)

    map("]]", function()

        state.last()
        M.redraw()

    end)

    map("<C-f>", function()

        state.jump(5)
        M.redraw()

    end)

    map("<C-b>", function()

        state.jump(-5)
        M.redraw()

    end)

    map("s", function()

        local n = vim.v.count

        if n > 0 then

            if state.goto_record(n) then
                M.redraw()
            end

        end

    end)

    map("q", function()

        if state.mode() == "INSERT" then
            return
        end

        vim.api.nvim_win_close(M.win, true)

    end)

    map("j", function()

        if state.next_field() then
            M.redraw()
        end

    end)

    map("k", function()

        if state.prev_field() then
            M.redraw()
        end

    end)

    map("i", function()

        state.set_mode("INSERT")
        M.redraw()
        editor.open()

    end)

    map("S", function()

        state.sort_by("ПІБ")
        state.first()
        M.redraw()

    end)

    map("n", function()

        state.new_record()
        M.redraw()

        state.set_mode("INSERT")
        M.redraw()

        editor.open()

    end)

    map("dd", function()

        if state.delete_current() then
            M.redraw()
        else
            vim.notify(
                "Не можна видалити останню картку",
                vim.log.levels.WARN
            )
        end

    end)

    map("yy", function()

        state.copy_current()

        vim.notify("Картку скопійовано")

    end)

    map("p", function()

        if state.paste_after() then
            M.redraw()
        end

    end)

    map("u", function()

        if state.undo_last() then
            M.redraw()
            vim.api.nvim_echo({
                { "Операцію скасовано", "Normal" }
            }, false, {})
        end

    end)

    map("/", function()

        vim.ui.input({
            prompt = "Пошук ПІБ: "
        }, function(text)

            if text then
                state.find(text)
                M.redraw()
            end

        end)

    end)

end

---------------------------------------------------------

function M.open()

    if M.win and vim.api.nvim_win_is_valid(M.win) then
        vim.api.nvim_win_close(M.win, true)
    end

    M.buf = vim.api.nvim_create_buf(false, true)

    vim.bo[M.buf].buftype = "nofile"
    vim.bo[M.buf].bufhidden = "wipe"
    vim.bo[M.buf].swapfile = false

    local width = math.floor(vim.o.columns * 0.75)
    local height = math.floor(vim.o.lines * 0.85)

    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    M.win = vim.api.nvim_open_win(M.buf, true, {

        relative = "editor",

        width = width,
        height = height,

        row = row,
        col = col,

        border = "rounded",
        style = "minimal",

    })

    bind_keys()

    M.redraw()

end

function M.focus()

    if M.win and vim.api.nvim_win_is_valid(M.win) then
        vim.api.nvim_set_current_win(M.win)
    end

end

function M.close_editor()
    state.set_mode("NORMAL")
    M.redraw()
    M.focus()
end

---------------------------------------------------------

return M
