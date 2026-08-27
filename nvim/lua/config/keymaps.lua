-- =============================================================================
-- KEYMAPS
-- =============================================================================
local function map(m, l, r) vim.keymap.set(m, l, r, { silent = true }) end

map('n', '<F6>', ':set list!<CR>')  
map('n', '<F8>', ':set number!<CR>')
map('n', '<F7>', ':set wrap!<CR>')
map('n', '<F9>', ':setlocal spell!<CR>')
map('n', '<C-j>', ':bn<CR>')
map('n', '<C-k>', ':bp<CR>')

-- FZF
map('n', '<leader>ff', ':Files<CR>')
map('n', '<leader>fg', ':Rg<CR>')
map('n', '<leader>fb', ':Buffers<CR>')
map('n', '<leader>fr', ':History<CR>')

-- ORG
map('n', '<leader>oa', ':OrgAgenda<CR>')
map('n', '<leader>oc', ':OrgCapture<CR>')
map('n', '<leader>ot', ':OrgTodoToggle<CR>')

map('i', '<Up>', '<cmd>normal! g<Up><CR>')
map('i', '<Down>', '<cmd>normal! g<Down><CR>')


-- =============================================================================
-- ФАЙЛОВИЙ МЕНЕДЖЕР LF 
-- =============================================================================
local lf_win = nil
local lf_buf = nil

local function toggle_lf()
    -- 1. Якщо вікно вже відкрите
    if lf_win and vim.api.nvim_win_is_valid(lf_win) then
        if vim.api.nvim_get_current_win() == lf_win then
            if lf_buf and vim.api.nvim_buf_is_valid(lf_buf) then
                vim.api.nvim_buf_delete(lf_buf, { force = true })
            else
                vim.api.nvim_win_close(lf_win, true)
            end
            lf_win = nil
            lf_buf = nil
            return
        else
            vim.api.nvim_set_current_win(lf_win)
            vim.cmd("startinsert")
            return
        end
    end

    -- 2. Створюємо новий файл для вибору
    local selection_file = vim.fn.tempname()

    -- 3. Відкриваємо чистий спліт знизу
    vim.cmd("botright 15new")
    lf_win = vim.api.nvim_get_current_win()
    lf_buf = vim.api.nvim_get_current_buf()

    vim.bo[lf_buf].buftype = 'nofile'
    vim.bo[lf_buf].bufhidden = 'wipe'
    vim.bo[lf_buf].buflisted = false
    
    -- Вимикаємо перевірку орфографії для цього вікна
    vim.wo[lf_win].spell = false
    vim.wo[lf_win].statusline = "%#StatusLine# 📁 LF | [<leader>e]: Закрити LF | [Ctrl+h]: Вгору/Вниз "

    -- 4. Запуск lf
    vim.fn.termopen(string.format('lf -selection-path="%s"', selection_file), {
        on_exit = function()
            local choice = nil

            if vim.fn.filereadable(selection_file) == 1 then
                local lines = vim.fn.readfile(selection_file)
                vim.fn.delete(selection_file)

                if #lines > 0 and lines[1] ~= "" then
                    choice = lines[1]
                end
            end

            -- Очищаємо буфер термінала
            if lf_buf and vim.api.nvim_buf_is_valid(lf_buf) then
                vim.api.nvim_buf_delete(lf_buf, { force = vim.bo[lf_buf].buftype == "terminal" and true or { force = true} })
            end

            lf_win = nil
            lf_buf = nil

            -- Відкриваємо файл, якщо він був обраний
            if choice then
                vim.cmd("edit " .. vim.fn.fnameescape(choice))
            end
        end,
    })

    vim.cmd("startinsert")
end

-- Гарячі клавіші
vim.keymap.set({'n', 't'}, '<leader>e', toggle_lf, { desc = "Toggle LF" })
vim.keymap.set({'n', 't'}, '<leader>у', toggle_lf, { desc = "Toggle LF" })

-- Навігація вгору / вниз по Ctrl+h
vim.keymap.set('t', '<C-h>', function()
    vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes([[<C-\><C-n><C-w>k]], true, true, true),
        'n',
        false
    )
end, { desc = "З LF у верхнє вікно" })

vim.keymap.set('n', '<C-h>', function()
    if lf_win and vim.api.nvim_win_is_valid(lf_win) then
        vim.api.nvim_set_current_win(lf_win)
        vim.cmd("startinsert")
    end
end, { desc = "У нижнє вікно LF" })

-- =============================================================================
-- Таблиці
-- =============================================================================
vim.api.nvim_create_user_command('MakeTable', function(opts)
    if not vim.bo.modifiable then
        print("Цей буфер захищено від змін!")
        return
    end

    local r1, r2 = opts.line1, opts.line2
    vim.cmd(string.format([[%d,%dg/^\s*$/d]], r1, r2))
    vim.cmd(string.format([[%d,%ds/^/| /]], r1, r2))
    vim.cmd(string.format([[%d,%ds/$/ | |/]], r1, r2))
    vim.fn.append(r1 - 1, {"| Дані | Коментар |", "| --- | --- |"})
    vim.cmd(string.format([[%d,%d!column -t -s '|' -o '|']], r1, r2 + 2))
end, { range = true })

map('n', '<leader>t', ':MakeTable<CR>')
map('v', '<leader>t', ':<C-u>MakeTable<CR>')
