local M = {}

local state = require("awards53.state")
local utils = require("awards53.utils")

M.buf = nil
M.win = nil

function M.open()
    local record = state.current_record()
    local field = state.field_name()

    -- Створюємо буфер та відкриваємо його у новій вкладці
    M.buf = vim.api.nvim_create_buf(false, true)
    vim.cmd("tabedit +buf" .. M.buf)
    M.win = vim.api.nvim_get_current_win()

    -- Налаштування буфера 
    local bo = vim.bo[M.buf]
    bo.bufhidden, bo.swapfile, bo.filetype, bo.spelllang = "wipe", false, "org", "uk,en"
    
    -- Заповнюємо буфер текстом поля
    vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, record[field] or {})
    require("awards53.abbreviations").register_buffer_abbreviations(M.buf)
    
    vim.api.nvim_buf_set_name(M.buf, string.format("Awards53 %d/%d (%s)", state.index(), state.count(), field))
    vim.api.nvim_win_set_cursor(M.win, { 1, 0 }) -- Ставимо курсор на перший рядок

    -- Налаштування вікна редактора
    local wo = vim.wo[M.win]
    wo.spell, wo.statusline = true, "%!v:lua.require'awards53.editor'.render_status()"

    -- ГРУПА АВТОКОМАНД ТА КОМАНД
    local group = vim.api.nvim_create_augroup("Awards53Editor", { clear = true })

    -- Оновлення статус-рядка
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = M.buf, group = group, callback = function() vim.cmd("redrawstatus") end,
    })

    -- Спільна функція для збереження, яку викликатимуть і :w, і :W, і :Q
    local function save_and_notify()
        M.save_core()
        utils.info("Зміни збережено в org-файл!")
    end

    -- Перехоплення :w та створення :W
    vim.api.nvim_create_autocmd("BufWriteCmd", { buffer = M.buf, group = group, callback = save_and_notify })
    vim.api.nvim_buf_create_user_command(M.buf, "W", save_and_notify, {})

    -- Команда :Q та :Q!
    vim.api.nvim_buf_create_user_command(M.buf, "Q", function(opts)
        if not opts.bang then M.save_core() end -- Якщо без !, то спочатку зберігаємо
        vim.bo[M.buf].modified = false
        vim.cmd("tabclose!")
    end, { bang = true })

    -- Командні абревіатури
    vim.cmd("cnoreabbrev <buffer> q Q")
    vim.cmd("cnoreabbrev <buffer> q! Q!")

    -- Очищення при закритті
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(args)
            if tonumber(args.match) == M.win then
                state.set_mode("NORMAL")
                require("awards53.ui").redraw()
                vim.api.nvim_del_augroup_by_id(group)
            end
        end,
    })

    vim.cmd("startinsert")
end

-- ЯДРО ЗБЕРЕЖЕННЯ ДЛЯ ПОЛЯ
function M.save_core()
    if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end

    local record = state.current_record()
    local field = state.field_name()

    record[field] = vim.api.nvim_buf_get_lines(M.buf, 0, -1, false)
    vim.bo[M.buf].modified = false
    vim.cmd("redrawstatus")

    local src = state.get_source_buffer()
    if src and vim.api.nvim_buf_is_valid(src) then
        local file_path = vim.api.nvim_buf_get_name(src)

        state.sync_to_disk()
        
        vim.api.nvim_buf_call(src, function()
            vim.bo[src].modified = false
            local cmd = (file_path and file_path ~= "") and ("silent write! " .. vim.fn.fnameescape(file_path)) or "silent write!"
            vim.cmd(cmd)
        end)
    end
end

-- Рендеринг статус-рядка
function M.render_status()
    if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return "" end
    local modified = vim.bo[M.buf].modified and " [+] " or " "
    
    return string.format(
        " РЕДАКТУВАННЯ %d/%d (%s)%s │  :w — зберегти  │  :q — зберегти й вийти  │  :q! — скасувати зміни",
        state.index(), state.count(), state.field_name(), modified
    )
end

return M
