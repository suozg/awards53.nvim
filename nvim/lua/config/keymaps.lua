-- =============================================================================
-- 5. KEYMAPS
-- =============================================================================
local function map(m, l, r) vim.keymap.set(m, l, r, {silent=true}) end
map('n', '<F6>', ':set list!<CR>')  
map('n','<F8>',':set number!<CR>')
map('n','<F7>',':set wrap!<CR>')
map('n','<F9>',':setlocal spell!<CR>')
map('n','<C-j>',':bn<CR>')
map('n','<C-k>',':bp<CR>')

-- FZF
map('n','<leader>ff',':Files<CR>')
map('n','<leader>fg',':Rg<CR>')
map('n','<leader>fb',':Buffers<CR>')
map("n", "<leader>fr", ":History<CR>")

-- ORG
map('n','<leader>oa',':OrgAgenda<CR>')
map('n','<leader>oc',':OrgCapture<CR>')
map('n','<leader>ot',':OrgTodoToggle<CR>')

map('i', '<Up>', '<cmd>normal! g<Up><CR>')
map('i', '<Down>', '<cmd>normal! g<Down><CR>')

-- файловий менеджер lf 
-- <leader>e → открыть lf (split снизу)
-- Ctrl+k → вверх в редактор
-- Ctrl+j → обратно в lf
local lf_win = nil

-- Запуск lf (split знизу на 15 рядків, можна налаштувати висоту)
vim.keymap.set('n', '<leader>e', function()
    -- Якщо вікно вже відкрите і валідне — просто переходимо в нього
    if lf_win and vim.api.nvim_win_is_valid(lf_win) then
        vim.api.nvim_set_current_win(lf_win)
        vim.cmd("startinsert")
        return
    end

    -- Створюємо спліт знизу
    vim.cmd("botright 15split") 
    vim.cmd("terminal lf")
    vim.cmd("startinsert")
    lf_win = vim.api.nvim_get_current_win()
end)

-- Перехід з lf вгору в редактор (працює в режимі терміналу 't')
vim.keymap.set('t', '<C-k>', function()
    -- Емулюємо натискання Ctrl+\ Ctrl+n (вихід з режиму вводу терміналу)
    -- і відразу переходимо вгору
    vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes([[<C-\><C-n><C-w>k]], true, true, true),
        'n',
        false
    )
end)

-- Повернення в lf (з нормального режиму 'n' редактора)
vim.keymap.set('n', '<C-j>', function()
    if lf_win and vim.api.nvim_win_is_valid(lf_win) then
        vim.api.nvim_set_current_win(lf_win)
        vim.cmd("startinsert")
    else
        -- Якщо вікна немає (закрили), але натиснули C-j — просто відкриваємо заново
        vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes([[<leader>e]], true, true, true),
            'm',
            false
        )
    end
end)


-- =============================================================================
-- Команда створює таблицю з виділеного тексту або рядка
vim.api.nvim_create_user_command('MakeTable', function(opts)
    local r1, r2 = opts.line1, opts.line2
    vim.cmd(string.format([[%d,%dg/^\s*$/d]], r1, r2))
    vim.cmd(string.format([[%d,%ds/^/| /]], r1, r2))
    vim.cmd(string.format([[%d,%ds/$/ | |/]], r1, r2))
    vim.fn.append(r1 - 1, {"| Дані | Коментар |", "| --- | --- |"})
    vim.cmd(string.format([[%d,%d!column -t -s '|' -o '|']], r1, r2 + 2))
end, {range = true})

map('n', '<leader>t', ':MakeTable<CR>')
map('v', '<leader>t', ':MakeTable<CR>')

