local M = {}

local state = require("awards53.state")

M.buf = nil
M.win = nil

local utils = require("awards53.utils")


function M.open()
    local record = state.current_record()
    local field = state.field_name()

    -- 1. Створюємо нову вкладку
    vim.cmd("tabnew")
    M.buf = vim.api.nvim_get_current_buf()
    M.win = vim.api.nvim_get_current_win()

    -- Налаштування основного буфера
    vim.bo[M.buf].buftype = ""
    vim.bo[M.buf].bufhidden = "wipe"
    vim.bo[M.buf].swapfile = false
    vim.bo[M.buf].filetype = "org"

    -- Заповнюємо буфер текстом
    vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, record[field] or {})

    vim.api.nvim_buf_set_name(
        M.buf,
        string.format("Awards53 %d/%d (%s)", state.index(), state.count(), field)
    )

    -- Безпечно ставимо курсор на початок тексту
    local line_count = vim.api.nvim_buf_line_count(M.buf)
    local target_line = math.min(1, line_count)
    vim.api.nvim_win_set_cursor(M.win, { target_line, 0 })

    -- Увімкнення перевірки орфографії
    vim.opt_local.spell = true
    vim.opt_local.spelllang = "uk,en_us"

    -- Запускаємо первинну перевірку рнокпп при відкритті картки
    utils.highlight_rnokpp_in_buf(M.buf)
    
    local group = vim.api.nvim_create_augroup("Awards53Editor" .. M.win, { clear = true })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = group,
        buffer = M.buf,
        callback = function()
            vim.schedule(function()
                utils.highlight_rnokpp_in_buf(M.buf)
            end)
        end,
    })

    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(args)
            if tonumber(args.match) ~= M.win then
                return
            end
            state.set_mode("NORMAL")
            require("awards53.ui").redraw()
            vim.api.nvim_del_augroup_by_id(group)
        end,
    })

    vim.api.nvim_create_autocmd("BufWriteCmd", {
        buffer = M.buf,
        callback = function()
            M.save()
        end,
    })

    vim.api.nvim_buf_create_user_command(M.buf, "W", function()
        M.save()
    end, {})

    vim.cmd("startinsert")   -- Переходить в режим вставки перед першим символом

end


function M.save()
    local record = state.current_record()
    local field = state.field_name()

    -- Забираємо ВЕСЬ текст з M.buf
    local all = vim.api.nvim_buf_get_lines(M.buf, 0, -1, false)
    
    -- Записуємо чистий текст у стан
    record[field] = all
    
    -- Скидаємо прапорець модифікації ДО закриття вкладки,
    -- щоб Neovim не блокував процес через незбережені зміни
    vim.bo[M.buf].modified = false
    state.is_changed = true -- Фіксуємо, що текст поля було змінено!
    
    local src = state.get_source_buffer()
    if src and vim.api.nvim_buf_is_valid(src) then
        vim.cmd("silent Awards53Sync")
    end
    
    -- явно оновлюємо інтерфейс картки перед закриттям
    state.set_mode("NORMAL")
    require("awards53.ui").redraw()
    vim.cmd("tabclose!")
end

return M
