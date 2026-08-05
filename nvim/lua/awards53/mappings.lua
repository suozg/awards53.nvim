local M = {}

local utils = require("awards53.utils")

--- Реєструє маппінги для заданого буфера з автоматичним дублюванням на українську розкладку
function M.bind_buffer_keymaps(bufnr, keymaps, mode)
    mode = mode or "n"
    local opts = { buffer = bufnr, silent = true, noremap = true }

    for lhs, data in pairs(keymaps) do
        local callback = data[1]
        local need_redraw = data[2]

        local handler = function()
            local res = callback()
            
            -- Якщо прапорець redraw встановлений (true або функція), викликаємо його
            if need_redraw then
                if type(need_redraw) == "function" then
                    need_redraw()
                elseif type(need_redraw) == "boolean" and res ~= false then
                    -- Якщо це був просто булевий прапорець, викликаємо стандартний redraw з ui.lua, якщо він доступний
                    local ok, ui = pcall(require, "awards53.ui")
                    if ok and ui.redraw then
                        ui.redraw()
                    end
                end
            end
            return res
        end

        -- Реєструємо латинський маппінг
        vim.keymap.set(mode, lhs, handler, opts)

        -- Автоматично додаємо українську розкладку через utils.translate_key
        local uk = utils.translate_key(lhs)
        if uk ~= lhs then
            vim.keymap.set(mode, uk, handler, opts)
        end
    end
end

return M
