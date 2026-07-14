-- =============================================================================
-- 8. STATUSLINE
-- =============================================================================
function _G.statusline()
    local function flag(opt_name, label, key)
        local enabled = vim.opt[opt_name]:get()
        return string.format("[%s:%s]", label, enabled and key or "off")
    end

    local spell_state = "OFF"
    if vim.opt.spell:get() then
        local lang = vim.opt.spelllang:get()[1]
        spell_state = (lang == "uk" and "UA" or (lang == "en_us" and "EN" or lang:upper()))
    end

    local bufs = vim.fn.getbufinfo({buflisted = 1})
    local b_idx = 0
    for i, b in ipairs(bufs) do if b.bufnr == vim.fn.bufnr('%') then b_idx = i break end end
    local b_stat = (#bufs > 1) and string.format(" [B:%d/%d] ", b_idx, #bufs) or ""

    return table.concat({
        " %f %m %y ", b_stat, "%=",
        flag("list", "LST", "F6"), " ",
        flag("wrap", "WRP", "F7"), " ",
        flag("number", "NUM", "F8"), " ",
        string.format("[SPELL:%s:F9]", spell_state),
        " %l/%L:%c "
    })
end


-- Прив'язуємо функцію до опції статусбара
vim.opt.statusline = "%!v:lua.statusline()"

-- Функція, яка динамічно змінює колір стандартного StatusLine залежно від режиму
local function update_statusline_color()
    -- Використовуємо defer_fn замість schedule, щоб дати командам розкладки 
    -- повністю завершити свою роботу (даємо мікрозатримку у 10 мілісекунд)
    vim.defer_fn(function()
        local mode = vim.fn.mode()
        
        if mode:match("^[nN]") then
            -- Normal режим (синій DWM)
            vim.api.nvim_set_hl(0, "StatusLine", { bg = "#005577", fg = "#ffffff", bold = true })
        elseif mode == "i" or mode == "ic" or mode == "ix" then
            -- Insert режим (зелений)
            vim.api.nvim_set_hl(0, "StatusLine", { bg = "#2e7d32", fg = "#ffffff", bold = true })
        elseif mode:match("^[vV\22]") then
            -- Visual режим
            vim.api.nvim_set_hl(0, "StatusLine", { bg = "#8f3f71", fg = "#ffffff", bold = true })
        elseif mode == "t" then
            -- Режим терміналу
            vim.api.nvim_set_hl(0, "StatusLine", { bg = "#d65d0e", fg = "#ffffff", bold = true })
        else
            -- Інші режими
            vim.api.nvim_set_hl(0, "StatusLine", { bg = "#3c3836", fg = "#ebdbb2" })
        end
        
        -- Примусово перемальовуємо статусбар після зміни кольору
        vim.cmd("redrawstatus")
    end, 10) -- затримка 10мс
end

-- Створюємо автокоманди
local status_group = vim.api.nvim_create_augroup("StatusLineModeColors", { clear = true })

vim.api.nvim_create_autocmd({ 
    "ModeChanged", 
    "BufEnter", 
    "WinEnter",
    "InsertLeave",
    "InsertEnter"
}, {
    group = status_group,
    callback = update_statusline_color,
})

update_statusline_color()

