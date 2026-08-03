local M = {}

function M.open()
    -- Створюємо буфер без створення зайвих вкладки та з автоматичним видаленням при закритті
    local buf = vim.api.nvim_create_buf(false, true)

    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false

    local lines = {
        "НАВІГАЦІЯ",
        "────────────────────────────",
        "h / l       попередня / наступна картка",
        "[[ ]]       перша / остання",
        "H / L       ±5 карток",
        "j / k       попереднє / наступне поле",
        "",
        "ПОШУК",
        "────────────────────────────",
        "/           пошук",
        "/g          пошук в полі",
        "n / N       наступний / попередній",
        "S / O       сортування за алфавітом / офіцери першими",
        "",
        "РЕДАГУВАННЯ:",
        "Картка",
        "────────────────────────────",
        "A           нова картка",
        "dd          вирізати картку",
        "yy          копіювати картку",
        "dp          виокремити картку в файл ./fork.org", 
        "p           вставити картку",
        "u           відмінити дію з карткой",
        "",
        "Поля",
        "────────────────────────────",
        "F           додати поле",
        "B           видалити поле",
        "J / K       перемістити поле",
        "e / E       склеїти рядки поля / .. в усіх картках",
        "R / X       формат поля з РНОКПП / .. для усіх карток",
        "0           схлопнути пусті поля карток",
        "i           редагувати поле редакторі",
        "",
        "q або ESC   закрити",
    }

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    -- Вираховуємо розміри для охайного плаваючого вікна по центру екрана
    local width = 60
    local height = #lines
    local ui = vim.api.nvim_list_uis()[1]
    local vim_width = ui and ui.width or 120
    local vim_height = ui and ui.height or 40

    local row = math.floor((vim_height - height) / 2)
    local col = math.floor((vim_width - width) / 2)

    local opts = {
        style = "minimal",
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        border = "rounded",
    }

    -- Відкриваємо у плаваючому вікні поверх інтерфейсу плагіна
    local win = vim.api.nvim_open_win(buf, true, opts)
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false

    -- Закриття по q або ESC без залишкових буферів
    local function close_help()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end

    vim.keymap.set("n", "q", close_help, { buffer = buf, noremap = true, silent = true })
    vim.keymap.set("n", "<Esc>", close_help, { buffer = buf, noremap = true, silent = true })
end

return M
