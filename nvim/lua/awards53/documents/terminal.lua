local M = {}

local config = require("awards53.documents.config")

function M.pick(callback)
    -- 1. Розраховуємо розміри для плаваючого вікна (60% від розміру екрана)
    local width = math.floor(vim.o.columns * 0.6)
    local height = math.floor(vim.o.lines * 0.6)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    -- 2. Створюємо тимчасовий буфер для термінала
    local buf = vim.api.nvim_create_buf(false, true)
    
    -- 3. Налаштовуємо параметри плаваючого вікна
    local win_opts = {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = "rounded", -- округла рамка
    }

    -- 4. Відкриваємо плаваюче вікно
    local win = vim.api.nvim_open_win(buf, true, win_opts)

    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false

    -- 5. Запускаємо fzf всередині плаваючого вікна
    vim.fn.termopen({
        "doc53-picker",
        config.template_dir,
    }, {
        on_exit = function(_, code)
            vim.schedule(function()
                -- Закриваємо вікно та буфер
                if vim.api.nvim_win_is_valid(win) then
                    vim.api.nvim_win_close(win, { force = true })
                end
                if vim.api.nvim_buf_is_valid(buf) then
                    vim.api.nvim_buf_delete(buf, { force = true })
                end

                if code ~= 0 then
                    return
                end

                local file = config.selection_file
                if vim.fn.filereadable(file) == 0 then
                    return
                end

                local path = vim.fn.readfile(file)[1]
                callback(path)
            end)
        end,
    })

    vim.cmd("startinsert")
end

return M
