local M = {}

function M.open()
    local buf = vim.api.nvim_create_buf(false, true)

    vim.cmd("tabnew")
    vim.api.nvim_win_set_buf(0, buf)

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
        "РЕДАГУВАННЯ",
        "────────────────────────────",
        "A           нова картка",
        "dd          вирізати картку",
        "yy          копіювати картку",
        "p           вставити картку",
        "u           відмінити дію з карткой",
        "",
        "ПОЛЯ",
        "────────────────────────────",
        "F           додати поле",
        "B           видалити поле",
        "J / K       перемістити поле",
        "e           склеїти рядки поля",
        "E           склеїти рядки поля в усіх картках",
        "R / X       формат поля з РНОКПП / .. для усіх карток",
        "0           схлопнути пусті поля карток",
        "i           редагувати поле редакторі",
        "",
        "q або ESC   закрити",
    }

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf,0,-1,false,lines)
    vim.bo[buf].modifiable = false

    vim.keymap.set("n","q","<cmd>bd!<CR>",{buffer=buf})
    vim.keymap.set("n","<Esc>","<cmd>bd!<CR>",{buffer=buf})
end

return M
