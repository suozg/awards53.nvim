local M = {}

local state = require("awards53.state")
local utils = require("awards53.utils")
local actions = require("awards53.actions")

M.buf = nil      -- Буфер редагування тексту
M.win = nil      -- Вікно редагування тексту
M.help_buf = nil -- Буфер підказок
M.help_win = nil -- Вікно підказок внизу

-- Текст підказок, який буде зафіксовано внизу екрана
local help_lines = {
    "  R   - Форматувати РНОКПП/ВЧ у поточному полі           |  e   - Склеїти рядки поточного поля в один рядок",
    "  X   - Форматувати РНОКПП/ВЧ у цьому полі ВСІХ КАРТОК   |  E   - Склеїти рядки цього поля у ВСІХ картках файлу",
    "  :w  - Зберегти зміни    │   :q  - Зберегти та вийти    │  :q! - Вийти без збереження",
}

-- Функція для підрахунку статистики (рядки, слова, символи)
local function get_text_stats()
    if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
        return { lines = 0, words = 0, chars = 0 }
    end

    local lines = vim.api.nvim_buf_get_lines(M.buf, 0, -1, false)
    local line_count = #lines
    local word_count = 0
    local char_count = 0

    for _, line in ipairs(lines) do
        -- Рахуємо символи (з урахуванням UTF-8)
        char_count = char_count + vim.str_utfindex(line)
        
        -- Рахуємо слова (розбиваємо за пробілами та розділовими знаками)
        for _ in string.gmatch(line, "[%w_А-Яа-яЄєІіЇїҐґ']+") do
            word_count = word_count + 1
        end
    end

    return {
        lines = line_count,
        words = word_count,
        chars = char_count
    }
end

function M.open()
    local record = state.current_record()
    local field = state.field_name()

    -- 1. Створюємо основний буфер редагування та відкриваємо у новій вкладці
    M.buf = vim.api.nvim_create_buf(false, true)
    vim.cmd("tabedit +buf" .. M.buf)
    M.win = vim.api.nvim_get_current_win()

    -- Налаштування основного буфера
    local bo = vim.bo[M.buf]
    bo.bufhidden, bo.swapfile, bo.filetype, bo.spelllang = "wipe", false, "org", "uk,en"
    
    -- Заповнюємо тільки чистим вмістом поля
    local content_lines = vim.deepcopy(record[field] or {})
    vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, content_lines)
    require("awards53.abbreviations").register_buffer_abbreviations(M.buf)
    
    vim.api.nvim_buf_set_name(M.buf, string.format("Awards53 %d/%d (%s)", state.index(), state.count(), field))
    vim.api.nvim_win_set_cursor(M.win, { 1, 0 })

    -- Налаштування основного вікна
    local wo = vim.wo[M.win]
    wo.spell, wo.statusline = true, "%!v:lua.require'awards53.editor'.render_status()"

    -- 2. СТВОРЮЄМО СЛУЖБОВЕ ВІКНО ПІДКАЗОК (Притиснуте до низу)
    M.help_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(M.help_buf, 0, -1, false, help_lines)
    
    -- Робимо буфер підказок незмінним (Read-Only)
    local h_bo = vim.bo[M.help_buf]
    h_bo.buftype, h_bo.bufhidden, h_bo.swapfile, h_bo.modifiable = "nofile", "wipe", false, false

    -- Ділимо екран горизонтально вниз (botright split)
    vim.cmd("botright split")
    M.help_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.help_win, M.help_buf)
    
    -- Фіксуємо висоту вікна підказок за кількістю рядків
    vim.api.nvim_win_set_height(M.help_win, #help_lines)
    
    -- Стилізуємо вікно підказок
    local h_wo = vim.wo[M.help_win]
    h_wo.number, h_wo.relativenumber, h_wo.signcolumn, h_wo.colorcolumn, h_wo.spell = false, false, "no", "", false
    h_wo.winfixheight = true -- Забороняємо Neovim змінювати висоту цього спліту
   

    vim.api.nvim_set_hl(0, "Awards53Help", {
        fg = "#897d6d",
        bg = "#3C3838",
    })

    vim.api.nvim_set_hl(0, "Awards53HelpText", {
        fg = "#897d6d",
        bg = "#3C3838",
        bold = false,
    })
    h_wo.winhighlight =
    "Normal:Awards53Help,NormalNC:Awards53Help,SignColumn:Awards53Help"
    
    -- Встановлюємо динамічний статус-рядок для панелі підказок!
    h_wo.statusline = "%!v:lua.require'awards53.editor'.render_help_status()"

    -- Підсвічуємо текст підказок у нижньому вікні гарним кольором
    local ns = vim.api.nvim_create_namespace("awards53_editor_help")
    for i = 0, #help_lines - 1 do
        vim.api.nvim_buf_add_highlight(M.help_buf, ns, "Awards53EditorHelpText", i, 0, -1)
    end

    -- Повертаємо фокус назад у вікно редагування тексту
    vim.api.nvim_set_current_win(M.win)

    -- 3. АВТОКОМАНДИ ТА ГАРЯЧІ КЛАВІШІ
    local group = vim.api.nvim_create_augroup("Awards53Editor", { clear = true })

    -- Оновлення статус-рядків при зміні тексту (для миттєвого перерахунку слів/букв)
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = M.buf, 
        group = group, 
        callback = function() 
            vim.cmd("redrawstatus") 
        end,
    })

    -- Спільна функція для збереження
    local function save_and_notify()
        M.save_core()
        utils.info("Зміни збережено в org-файл!")
    end

    -- Перехоплення збереження
    vim.api.nvim_create_autocmd("BufWriteCmd", { buffer = M.buf, group = group, callback = save_and_notify })
    vim.api.nvim_buf_create_user_command(M.buf, "W", save_and_notify, {})

    -- Команда :Q та :Q!
    vim.api.nvim_buf_create_user_command(M.buf, "Q", function(opts)
        if not opts.bang then M.save_core() end
        vim.bo[M.buf].modified = false
        vim.cmd("tabclose!")
    end, { bang = true })

    -- Командні абревіатури
    vim.cmd("cnoreabbrev <buffer> q Q")
    vim.cmd("cnoreabbrev <buffer> q! Q!")

    -- Локальні клавіші для редактора (Normal Mode)
    local editor_keymaps = {
        ["R"] = { function() 
            M.save_core(true) 
            actions.format_rnokpp_in_current_card()
            M.refresh_editor_buffer()
        end, "Форматування РНОКПП виконано" },

        ["X"] = { function() 
            M.save_core(true)
            actions.format_rnokpp_in_all_cards()
            M.refresh_editor_buffer()
        end, "Заміна РНОКПП у всіх картках виконана" },

        ["e"] = { function() 
            M.save_core(true)
            state.flatten_current_field()
            M.refresh_editor_buffer()
        end, "Рядки поля склеєно" },

        ["E"] = { function() 
            M.save_core(true)
            state.flatten_field_globally()
            M.refresh_editor_buffer()
        end, "Рядки поля склеєно в усіх картках" },
    }
    
    local key_opts = { buffer = M.buf, silent = true, noremap = true }
    for lhs, data in pairs(editor_keymaps) do
        local func, desc = data[1], data[2]
        local handler = function()
            func()
            utils.info(desc)
        end
        vim.keymap.set("n", lhs, handler, key_opts)
        
        -- Використовуємо централізовану функцію!
        local uk = utils.translate_key(lhs)
        if uk ~= lhs then 
            vim.keymap.set("n", uk, handler, key_opts) 
        end
    end

    -- Очищення при закритті вікна редактора
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(args)
            if tonumber(args.match) == M.win then
                if M.help_win and vim.api.nvim_win_is_valid(M.help_win) then
                    pcall(vim.api.nvim_win_close, M.help_win, true)
                end
                state.set_mode("NORMAL")
                require("awards53.ui").redraw()
                vim.api.nvim_del_augroup_by_id(group)
            end
        end,
    })
end

-- Оновлення вмісту основного буфера редактора після дій
function M.refresh_editor_buffer()
    if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end
    local record = state.current_record()
    local field = state.field_name()
    local content_lines = vim.deepcopy(record[field] or {})

    local cursor = vim.api.nvim_win_get_cursor(M.win)
    vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, content_lines)
    
    local max_line = #content_lines
    if cursor[1] > max_line then cursor[1] = max_line end
    if cursor[1] < 1 then cursor[1] = 1 end
    pcall(vim.api.nvim_win_set_cursor, M.win, cursor)
end

-- Чисте збереження
function M.save_core(silent_write)
    if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end

    local record = state.current_record()
    local field = state.field_name()

    -- Отримуємо тільки чистий текст користувача
    local clean_lines = vim.api.nvim_buf_get_lines(M.buf, 0, -1, false)

    -- Видаляємо кінцеві порожні рядки
    while #clean_lines > 0 and vim.trim(clean_lines[#clean_lines]) == "" do
        table.remove(clean_lines)
    end

    record[field] = clean_lines
    vim.bo[M.buf].modified = false
    vim.cmd("redrawstatus")

    local src = state.get_source_buffer()
    if src and vim.api.nvim_buf_is_valid(src) then
        local file_path = vim.api.nvim_buf_get_name(src)

        state.sync_to_disk()
        
        vim.api.nvim_buf_call(src, function()
            vim.bo[src].modified = true
            
            if file_path and file_path ~= "" then
                pcall(vim.cmd, "silent write! " .. vim.fn.fnameescape(file_path))
                if not silent_write then
                    vim.bo[src].modified = false
                end
            end
        end)
    end
end

-- Рендеринг статус-рядка для верхнього робочого вікна
function M.render_status()
    if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return "" end
    local modified = vim.bo[M.buf].modified and " [+] " or " "
    
    return string.format(
        " РЕДАКТУВАННЯ %d/%d (%s)%s │ Натисніть i для вводу тексту │ :w - зберегти │ :q - вийти",
        state.index(), state.count(), state.field_name(), modified
    )
end

-- РЕНДЕРИНГ ДЛЯ ПАНЕЛІ ПІДКАЗОК (відображає статистику)
function M.render_help_status()
    local stats = get_text_stats()
    
    -- Ліва частина: Статистика поточного тексту
    local left = string.format(
        " 📊 Символів: %d  │  Слів: %d  │  Рядків: %d",
        stats.chars, stats.words, stats.lines
    )
    
    -- Права частина: Маркер панелі
    local right = " * "
    -- Розраховуємо пробіли для вирівнювання праворуч
    local width = vim.api.nvim_win_get_width(M.help_win or 0)
    local padding = width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right)
    if padding < 1 then padding = 1 end

    return left .. string.rep(" ", padding) .. right
end

return M
