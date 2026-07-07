local M = {}

local header = require("awards53.header")
local body = require("awards53.body")
local state = require("awards53.state")
local editor = require("awards53.editor")
local utils = require("awards53.utils")

M.body_buf = nil
M.body_win = nil

---------------------------------------------------------

local function render_body()

    local lines = {}

    vim.list_extend(lines, header.render())
    vim.list_extend(lines, body.render())

    return lines

end

---------------------------------------------------------
function M.redraw()

    if not (M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf)) then
        return
    end

    vim.bo[M.body_buf].modifiable = true

    vim.api.nvim_buf_set_lines(
        M.body_buf,
        0,
        -1,
        false,
        render_body()
    )

    vim.bo[M.body_buf].modifiable = false
  
    utils.highlight_rnokpp_in_buf(M.body_buf)
end
---------------------------------------------------------
-- local function map(lhs, rhs)
--     print("Creating mapping:", lhs)
--     vim.keymap.set(
--         "n",
--         lhs,
--         rhs,
--         {   
--             buffer = M.body_buf,
--             silent = true }
--     )
-- end
-- Ваша таблиця ua залишається без змін
local ua = {
    h = "р", j = "о", k = "л", l = "д", i = "ш", a = "ф", s = "і", d = "в", f = "а", g = "п", y = "н", u = "г", n = "т", p = "з",
    H = "Р", J = "О", K = "Л", L = "Д", I = "Ш", A = "Ф", S = "І", D = "В", F = "А", G = "П", Y = "Н", U = "Г", N = "Т", P = "З",
    -- Додамо спецсимволи, якщо вони використовуються в маппінгах
    ["["] = "х", ["]"] = "ї",
    ["/"] = ".", ["?"] = ",",
}

-- Допоміжна функція для посимвольного перекладу комбінацій (наприклад, "dd" -> "вв")
local function translate_to_uk(str)
    -- Якщо це керуюча клавіша типу <C-f> або :w<CR>, повертаємо її як є
    if str:match("<.*>") or str:match("^:") then
        return str
    end

    local result = ""
    -- Розбиваємо рядок на окремі символи
    for i = 1, #str do
        local char = str:sub(i, i)
        result = result .. (ua[char] or char)
    end
    return result
end

local function map(lhs, rhs)
    local opts = {
        buffer = M.body_buf,
        silent = true,
    }

    -- 1. Реєструємо оригінальний англійський маппінг
    vim.keymap.set("n", lhs, rhs, opts)

    -- 2. Перекладаємо та реєструємо український відповідник
    local uk = translate_to_uk(lhs)
    if uk ~= lhs then
        vim.keymap.set("n", uk, rhs, opts)
    end
end

---------------------------------------------------------
local function bind_keys()

    local cfg = require("awards53")

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
        state.sort_by(cfg.config.default_sort)
        state.first()
        M.redraw()
    end)

    map("A", function()
        state.new_record()
        M.redraw()
        state.set_mode("INSERT")
        M.redraw()
        editor.open()
    end)
    
    map("F", function()
        if state.new_field() then
            M.redraw()
            utils.info("Додано нове поле №" .. state.field_name())
        end
    end)
    
    map("dd", function()
        state.copy_current()
        if state.delete_current() then
            M.redraw()
            utils.info("Картку вирізано")
        else
            utils.error("Не можна видалити останню картку")
        end
    end)

    map("yy", function()
        state.copy_current()
        utils.info("Картку скопійовано")
    end)

    map("p", function()
        if state.paste_after() then
            M.redraw()
        end
    end)

    map("u", function()
        if state.undo_last() then
            M.redraw()
            utils.info("Операцію скасовано")
        end
    end)

    map("/", function()
        vim.ui.input({
            prompt = "Пошук " .. cfg.config.default_sort .. ": "
        }, function(text)
            if text and text ~= "" then
                state.find(text, 1)
                M.redraw()
            end
        end)
    end)

    map("?", function()

        vim.ui.select(state.headers_list(), {
            prompt = "Поле:"
        }, function(field)

            if not field then
                return
            end

            vim.ui.input({
                prompt = "Пошук (" .. field .. "): "
            }, function(text)

                if text and text ~= "" then
                    state.find(text, 1, field)
                    M.redraw()
                end

            end)

        end)

    end)

    map("n", function()
        if state.find_next() then
            M.redraw()
        end
    end)

    map("N", function()
        if state.find_next(-1) then
            M.redraw()
        end
    end)

    local actions = require("awards53.actions")

    -- Натискання великої 'O' — сортує весь список (офіцери на початок)
    map("O", function()
        actions.sort_officers_first()
        state.first()
        M.redraw()
    end)

    -- Натискання 'R' (РНОКПП) — виправляє форматування коду в Полі 2 поточної картки
    map("R", function()
        actions.format_rnokpp_in_current_card()
        M.redraw()
    end)

    -- Натискання 'X' (eXpand) — примусово розгортає всі абревіатури у поточній картці
    map("X", function()
        actions.expand_abbr_in_current_card()
        M.redraw()
    end)


end

---------------------------------------------------------
function M.open()

    M.body_buf = vim.api.nvim_create_buf(false, true)

    vim.bo[M.body_buf].buftype = "nofile"
    vim.bo[M.body_buf].bufhidden = "wipe"
    vim.bo[M.body_buf].swapfile = false

    vim.cmd("tabnew")

    M.body_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.body_win, M.body_buf)

    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = M.body_buf,
        callback = function()
            if state.is_changed then
                local org_buf = state.get_source_buffer()
                if org_buf and vim.api.nvim_buf_is_valid(org_buf) then
                    local success, err = pcall(function()
                        vim.cmd("silent Awards53Sync")
                    end)
                    
                    if success then
                        vim.bo[org_buf].modified = true
                    else
                        utils.warn("Не вдалося синхронізувати зміни: розділ секції було пошкоджено або видалено.")
                    end
                end
            end
            M.body_buf = nil
            M.body_win = nil
        end,
    })

    vim.api.nvim_buf_set_name(M.body_buf, "Awards53")
    vim.wo[M.body_win].statusline =
    "%!v:lua.require'awards53.status'.render()"

    vim.wo[M.body_win].number = false
    vim.wo[M.body_win].relativenumber = false
    vim.wo[M.body_win].signcolumn = "no"
    
    bind_keys()
    
    -- Замість помилки це просто закриє картки (так само як :q).
    vim.keymap.set("n", ":w<CR>", ":q<CR>", { buffer = M.body_buf, silent = true })

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
    M.focus()
end

---------------------------------------------------------

---------------------------------------------------------

return M
