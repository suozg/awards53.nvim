-- ui.lua
--
local M = {}

local header = require("awards53.header") 
local body = require("awards53.body") 
local state = require("awards53.state") 
local editor = require("awards53.editor") 
local utils = require("awards53.utils") 
local actions = require("awards53.actions") 
local move_karta = require("awards53.move_karta")
local mappings = require("awards53.mappings")

M.body_buf = nil 
M.body_win = nil 

local cfg = require("awards53")
local NS_ID = cfg.ns_fields or vim.api.nvim_create_namespace("awards53_fields") 
local syntax_group = "Awards53ActiveField" 

-- Оголошуємо дефолтні кольори для інтерфейсу картки.
-- Вказуємо default = true, щоб користувач міг перевизначити їх у своєму theme.lua за бажанням.
local function setup_awards_highlights()
    -- Базове підсвічування поля (за замовчуванням як CursorLine)
    vim.cmd("highlight default link Awards53ActiveField CursorLine")
    
    -- Лінійки-розділювачі та рамки блоків ([#] ... .)
    vim.api.nvim_set_hl(0, "Awards53Separator", { link = "Comment", default = true })
    
    -- Префікс активного поля (зелений/акцентний блок)
    vim.api.nvim_set_hl(0, "Awards53ActiveFieldPrefix", { link = "String", default = true })
    
    -- Перший куточок-розділювач 
    vim.api.nvim_set_hl(0, "Awards53ActiveFieldSeparator", { link = "Title", default = true })
    
    -- Кінцевий куточок 
    vim.api.nvim_set_hl(0, "Awards53ActiveFieldSuffix", { link = "NonText", default = true })
    
    -- Помилка РНОКПП (червоний колір)
    vim.api.nvim_set_hl(0, "Awards53RnokppError", { link = "SpellBad", default = true })
end

-- Ініціалізуємо кольори при першому завантаженні модуля
setup_awards_highlights()

-- При будь-якій зміні теми (colorscheme gruvbox) відновлюємо кольори та перемальовуємо UI
vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("Awards53HighlightsAutoRestore", { clear = true }),
    callback = function()
        setup_awards_highlights()
        if M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf) then
            M.redraw()
        end
    end,
})

local function apply_field_highlighting(buf) 
    vim.api.nvim_buf_clear_namespace(buf, NS_ID, 0, -1) 
    local line_count = vim.api.nvim_buf_line_count(buf)
    
    local in_block = false

    for i = 0, line_count - 1 do
        local line = vim.api.nvim_buf_get_lines(buf, i, i + 1, false)[1]
        
        -- Перевіряємо початок блоку ([#])
        local is_bracket_line = line and (line:find("^%s*%[") ~= nil)
        -- Перевіряємо кінець блоку (. .)
        local is_dot_line = line and (line:match("^%s*%.") ~= nil)

        if is_bracket_line then
            in_block = true
        end

        -- Якщо ми всередині блоку (або на одному з обмежувачів), підсвічуємо весь рядок
        if in_block and line then
            vim.api.nvim_buf_set_extmark(buf, NS_ID, i, 0, {
                end_row = i,
                end_col = #line,
                hl_group = "Awards53Separator",
                priority = 100, 
            })
        end

        if is_dot_line then
            in_block = false
        end

        -- Підсвітка розділювача Поле 
        if line and line:match("󰓻") then
            local sep_len = #("")
            local first_sep = line:find("")
            local last_sep = nil
            
            if first_sep then
                -- Шукаємо другий куточок після першого
                last_sep = line:find("", first_sep + sep_len)
            end
            
            -- Визначаємо, де має закінчуватися базове тло
            local end_col = last_sep and (last_sep - 1) or #line
            
            -- ШАР 1: Базове підсвічування 
            vim.api.nvim_buf_set_extmark(buf, NS_ID, i, 0, {
                end_row = i,
                end_col = end_col,
                hl_group = syntax_group,
                hl_eol = false, -- Тло не до правого краю
                priority = 100,
            })
            
            if first_sep then
                -- ШАР 2: Зелений блок початку
                vim.api.nvim_buf_set_extmark(buf, NS_ID, i, 0, {
                    end_row = i,
                    end_col = first_sep - 1,
                    hl_group = "Awards53ActiveFieldPrefix",
                    priority = 200, 
                })
                
                -- ШАР 3: Перший куточок (зелений текст на бежевому тлі)
                vim.api.nvim_buf_set_extmark(buf, NS_ID, i, first_sep - 1, {
                    end_row = i,
                    end_col = first_sep - 1 + sep_len,
                    hl_group = "Awards53ActiveFieldSeparator",
                    priority = 200, 
                })
            end
            
            if last_sep then
                -- ШАР 4: Кінцевий куточок (бежевий текст на прозорому тлі)
                vim.api.nvim_buf_set_extmark(buf, NS_ID, i, last_sep - 1, {
                    end_row = i,
                    end_col = last_sep - 1 + sep_len,
                    hl_group = "Awards53ActiveFieldSuffix",
                    priority = 200, 
                })
            end
        end
    end
end

local function render_body() 
    local lines = {} 
    vim.list_extend(lines, header.render()) 
    vim.list_extend(lines, body.render()) 
    return lines 
end

local function update_ui_buffer_title()
    if not (M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf)) then return end

    local src_buf = state.get_source_buffer()
    local is_modified = state.is_changed

    if src_buf and vim.api.nvim_buf_is_valid(src_buf) and vim.bo[src_buf].modified then
        is_modified = true
    end
    -- Встановлюємо статус modified для буфера, щоб mini.tabline підхопив його
    vim.bo[M.body_buf].modified = is_modified
    local title = is_modified and "[+] Awards53" or "Awards53"
    pcall(vim.api.nvim_buf_set_name, M.body_buf, title)
end

-- Функція для оновлення кольору/підсвітки заголовка вікна
local function update_header_highlight()
    if state.is_changed then
        -- Якщо є зміни: встановлюємо яскраве підсвічування (наприклад, WarningMsg або спеціальну групу)
        vim.cmd("highlight! link OrgCardHeader WarningMsg")
    else
        -- Якщо змін немає: повертаємо стандартне підсвічування (наприклад, Title або Normal)
        vim.cmd("highlight! link OrgCardHeader Title")
    end
end

function M.redraw()
    
    -- 1. Синхронізуємо прапор модифікації поточного буфера з глобальним станом
    vim.bo.modified = state.is_changed

    -- 2. Оновлюємо колір заголовка
    update_header_highlight()
    
    if not (M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf)) then return end 

    local current_win = vim.api.nvim_get_current_win()
    local current_buf = vim.api.nvim_win_get_buf(current_win)

    local is_editing_card_buffer = (M.body_win and vim.api.nvim_win_is_valid(M.body_win))
        and (current_win == M.body_win)
        and (current_buf == M.body_buf)

    local saved_cursor = nil
    if is_editing_card_buffer then
        saved_cursor = vim.api.nvim_win_get_cursor(M.body_win)
    end

    vim.bo[M.body_buf].modifiable = true 
    vim.api.nvim_buf_set_lines(M.body_buf, 0, -1, false, render_body()) 
    vim.bo[M.body_buf].modifiable = false 
  
    utils.highlight_rnokpp_in_buf(M.body_buf) 
    apply_field_highlighting(M.body_buf) 

if is_editing_card_buffer and saved_cursor then
        local line_count = vim.api.nvim_buf_line_count(M.body_buf)
        if saved_cursor[1] > line_count then saved_cursor[1] = line_count end
        pcall(vim.api.nvim_win_set_cursor, M.body_win, saved_cursor)
    end

    update_ui_buffer_title()
    vim.cmd("redrawstatus!")
end


-- Відкриття розширеного вікна перегляду Undotree з генерацією DIFF (порівнянням змін)
function M.open_undotree_window()
    local entries = state.get_undo_list()

    if #entries == 0 then
        utils.info("Історія дій порожня")
        return
    end

    local list_lines = {}
    local seq_map = {}

    for idx, entry in ipairs(entries) do
        local mark = entry.is_current and "➔ " or "  "
        local line = string.format("%s[%d] %s", mark, entry.seq, entry.time)
        table.insert(list_lines, line)
        seq_map[idx] = entry.seq
    end

    -- Буфер для списку кроків
    local list_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, list_lines)

    -- Буфер для прев'ю / diff
    local preview_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[preview_buf].filetype = "diff"

    local total_width = math.min(vim.o.columns - 6, 110)
    local list_width = 24
    local preview_width = total_width - list_width - 3
    local height = math.min(#list_lines + 4, 20)

    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - total_width) / 2)

    -- Ліве вікно (Список кроків)
    local list_win = vim.api.nvim_open_win(list_buf, true, {
        relative = "editor",
        width = list_width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Історія (U) ",
        title_pos = "center",
    })

    -- Праве вікно (Порівняння змін / Diff)
    local preview_win = vim.api.nvim_open_win(preview_buf, false, {
        relative = "editor",
        width = preview_width,
        height = height,
        row = row,
        col = col + list_width + 2,
        style = "minimal",
        border = "rounded",
        title = " Різниця змін ",
        title_pos = "center",
    })

    vim.bo[list_buf].buftype = "nofile"
    vim.bo[list_buf].modifiable = false
    vim.bo[preview_buf].buftype = "nofile"

    local diff_ns = vim.api.nvim_create_namespace("Awards53UndoDiff")

    -- Функція генерації Diff між поточним станом та обраним seq
    local function update_preview()
        local cursor = vim.api.nvim_win_get_cursor(list_win)
        local selected_seq = seq_map[cursor[1]]

        if not (selected_seq and state.source_buffer and vim.api.nvim_buf_is_valid(state.source_buffer)) then
            return
        end

        -- 1. Беремо поточний текст із буфера
        local current_lines = vim.api.nvim_buf_get_lines(state.source_buffer, 0, -1, false)

        -- 2. Тимчасово переходимо до обраного seq і зчитуємо старий текст
        local target_lines = {}
        vim.api.nvim_buf_call(state.source_buffer, function()
            vim.cmd("silent! undo " .. selected_seq)
            target_lines = vim.api.nvim_buf_get_lines(state.source_buffer, 0, -1, false)
        end)

        -- Всі процедури виконуються миттєво і повертають користувача назад до поточного тексту
        local current_text = table.concat(current_lines, "\n")
        local target_text = table.concat(target_lines, "\n")

        -- 3. Генеруємо уніфікований Diff через нативний vim.diff()
        local diff_result = vim.diff(target_text, current_text, {
            algorithm = "myers",
            ctxlen = 3, -- показуємо по 3 суміжні рядки навколо зміни для контексту
        })

        local diff_lines = {}
        if diff_result == "" then
            diff_lines = { "  (Змін немає / Поточний стан)" }
        else
            diff_lines = vim.split(diff_result, "\n", { trimempty = true })
        end

        -- 4. Оновлюємо вміст правого буфера
        vim.bo[preview_buf].modifiable = true
        vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, diff_lines)
        vim.bo[preview_buf].modifiable = false

        -- 5. Застосовуємо кольорову підсвітку для рядків Diff
        vim.api.nvim_buf_clear_namespace(preview_buf, diff_ns, 0, -1)
        for i, line in ipairs(diff_lines) do
            local line_idx = i - 1
            if line:sub(1, 1) == "+" and not line:match("^%+%+%+") then
                -- Додані рядки (Зелений)
                vim.api.nvim_buf_set_extmark(preview_buf, diff_ns, line_idx, 0, {
                    end_row = line_idx,
                    end_col = #line,
                    hl_group = "DiffAdd",
                })
            elseif line:sub(1, 1) == "-" and not line:match("^%-%-%-") then
                -- Видалені рядки (Червоний)
                vim.api.nvim_buf_set_extmark(preview_buf, diff_ns, line_idx, 0, {
                    end_row = line_idx,
                    end_col = #line,
                    hl_group = "DiffDelete",
                })
            elseif line:match("^@@") then
                -- Заголовки блоків змін (Блакитний / Жовтий)
                vim.api.nvim_buf_set_extmark(preview_buf, diff_ns, line_idx, 0, {
                    end_row = line_idx,
                    end_col = #line,
                    hl_group = "DiffLine",
                })
            end
        end
    end

    -- Автоматичний виклик при русі курсора
    local augroup = vim.api.nvim_create_augroup("Awards53UndoDiffPreview", { clear = true })
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = augroup,
        buffer = list_buf,
        callback = update_preview,
    })

    -- Первинний виклик для підсвічування
    update_preview()

    local close_windows = function()
        pcall(vim.api.nvim_del_augroup_by_name, "Awards53UndoDiffPreview")
        if list_win and vim.api.nvim_win_is_valid(list_win) then
            vim.api.nvim_win_close(list_win, true)
        end
        if preview_win and vim.api.nvim_win_is_valid(preview_win) then
            vim.api.nvim_win_close(preview_win, true)
        end
    end

    -- Перехід до обраного стану при натисканні <Enter>
    vim.keymap.set("n", "<CR>", function()
        local cursor = vim.api.nvim_win_get_cursor(list_win)
        local selected_seq = seq_map[cursor[1]]
        close_windows()

        if selected_seq then
            if state.restore_to_seq(selected_seq) then
                M.redraw()
            end
        end
    end, { buffer = list_buf, silent = true })

    vim.keymap.set("n", "q", close_windows, { buffer = list_buf, silent = true })
    vim.keymap.set("n", "<Esc>", close_windows, { buffer = list_buf, silent = true })
end


local function bind_keys() 
    local cfg = require("awards53") 

    local keymaps = { 
        ["h"]   = { function() return state.prev() end, true }, 
        ["l"]   = { function() return state.next() end, true }, 
        ["[["]  = { function() state.first() end, true }, 
        ["]]"]  = { function() state.last() end, true }, 
        ["<H>"] = { function() state.jump(5) end, true }, 
        ["<L>"] = { function() state.jump(-5) end, true }, 
        
        ["g"] = { function() 
            local total_records = state.count()
            if total_records == 0 then return end

            local count = vim.v.count
            if count > 0 then
                state.goto_record(count)
                M.redraw()
            else
                vim.ui.input({ prompt = "Номер картки для переходу (1-" .. total_records .. "): " }, function(input)
                    local num = tonumber(input)
                    if num then
                        state.goto_record(num)
                        M.redraw()
                    end
                end)
            end
        end, false },
        
        ["j"]   = { function() return state.next_field() end, true },
        ["k"]   = { function() return state.prev_field() end, true },

        -- Перехід до поля за номером через лічильник (наприклад, натиснувши `3go` або перейшовши за промовтом)
        ["f"] = { function() 
            local total = #state.headers_list()
            if total == 0 then return end

            local count = vim.v.count
            if count > 0 then
                state.field = math.max(1, math.min(count, total))
                state.last_field = state.field
                M.redraw()
            else
                vim.ui.input({ prompt = "Номер поля для переходу (1-" .. total .. "): " }, function(input)
                    local num = tonumber(input)
                    if num then
                        state.field = math.max(1, math.min(num, total))
                        state.last_field = state.field
                        M.redraw()
                    end
                end)
            end
        end, false },
        
        ["J"]   = { function() return state.move_field_content_down() end, true }, 
        ["K"]   = { function() return state.move_field_content_up() end, true }, 
        
        -- Закладки
        ["m"]   = { function() state.toggle_bookmark() end, true },
        ["]m"]  = { function() return state.next_bookmark() end, true },
        ["[m"]  = { function() return state.prev_bookmark() end, true },

        ["i"]   = { function() 
            local editor_mod = require("awards53.editor")
            if editor_mod.win and vim.api.nvim_win_is_valid(editor_mod.win) then
                vim.api.nvim_set_current_win(editor_mod.win)
                return
            end
            state.set_mode("INSERT") 
            M.redraw() 
            editor_mod.open() 
        end, false },
        ["A"]   = { function() state.new_record() M.redraw() state.set_mode("INSERT") M.redraw() editor.open() end, false }, 
        
        ["F"]   = { function() if state.new_field() then M.redraw() utils.info("Додано нове поле №" .. state.field_name()) end end, false }, 
        ["F-"]  = { function() if state.new_field("-") then M.redraw() utils.info("Додано нове поле №" .. state.field_name() .. " із '-'") end end, false }, 
        ["B"]   = { function() 
            if state.delete_field() then 
                state.sync_to_disk() 
                M.redraw() utils.info("Поле видалено") 
            else utils.error("Не вдалося видалити поле") end 
        end, false }, 

        ["dd"]  = { function() 
            state.copy_current() 
            if state.delete_current() then utils.info("Картку вирізано") else utils.error("Не можна видалити останню картку") end 
        end, true }, 
        
        ["yy"]  = { function() state.copy_current() utils.info("Картку скопійовано") end, false }, 

        ["p"]   = { function() return state.paste_after() end, true }, 

        ["u"] = { function() 
            if state.undo_last() then 
                M.redraw() 
            end 
        end, false },

        ["<C-r>"] = { function() 
            if state.redo_last() then 
                M.redraw() 
            end 
        end, false },

        -- Відкриття вікна перегляду Undotree
        ["U"] = { function()
            M.open_undotree_window()
        end, false },

        ["dp"]  = { function() move_karta.move_to_fork() end, true },

        ["/"]   = { function() 
            vim.ui.input({ prompt = "Пошук " .. cfg.config.default_sort .. ": " }, function(t) if t and t ~= "" then state.find(t, 1) M.redraw() end end) 
        end, false }, 
        
        ["g/"]  = { function() 
            vim.ui.select(state.headers_list(), { prompt = "🔍 Шукати в полі:" }, function(f) 
                if f then vim.ui.input({ prompt = "Пошук (" .. f .. "): " }, function(t) if t and t ~= "" then state.find(t, 1, f) M.redraw() end end) end 
            end) 
        end, false }, 

        ["n"]   = { function() return state.find_next() end, true }, 
        ["N"]   = { function() return state.find_next(-1) end, true }, 
        ["0"]   = { function() return state.collapse_empty_fields_globally() end, true }, 
        ["O"]   = { function() actions.sort_officers_first() state.first() end, true }, 
        ["S"]   = { function() state.sort_by(cfg.config.default_sort) state.first() end, true }, 
        ["?"]   = { function() require("awards53.help").open() end, false }, 
    }

    -- Викликаємо централізоване мапування через новий модуль mappings.lua
    mappings.bind_buffer_keymaps(M.body_buf, keymaps, "n")
end

function M.open() 
    if not (M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf)) then
        M.body_buf = vim.api.nvim_create_buf(true, false) 
        
        vim.bo[M.body_buf].buftype = "acwrite" 
        vim.bo[M.body_buf].bufhidden = "hide" 
        vim.bo[M.body_buf].swapfile = false 
        
        update_ui_buffer_title()

        -- Логіка приховування курсора ===
        local orig_guicursor = vim.o.guicursor
        local cursor_grp = vim.api.nvim_create_augroup("Awards53HiddenCursorToggle", { clear = true })
        -- Робимо курсор прозорим при вході в буфер картки
        vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
            buffer = M.body_buf,
            group = cursor_grp,
            callback = function()
                vim.o.guicursor = "n-v-c:block-Awards53HiddenCursor"
            end,
        })
        -- Повертаємо стандартний курсор при виході (наприклад, при переході в редактор поля)
        vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
            buffer = M.body_buf,
            group = cursor_grp,
            callback = function()
                vim.o.guicursor = orig_guicursor
            end,
        })
        -- ===========================================

        local keys_to_disable = { 
            "<Up>", "<Down>", "<Left>", "<Right>", 
            "w", "b", "ge", "$", "^", "gg", "G" 
        }
        for _, key in ipairs(keys_to_disable) do
            vim.keymap.set("n", key, "<Nop>", { buffer = M.body_buf, noremap = true, silent = true })
        end

        bind_keys()

        local function save_card_action()
            local src_buf = state.get_source_buffer()
            if src_buf and vim.api.nvim_buf_is_valid(src_buf) then
                state.sync_to_disk()

                if vim.bo[src_buf].modified then
                    vim.api.nvim_buf_call(src_buf, function()
                        vim.cmd("silent! write")
                    end)
                end

                state.is_changed = false
                pcall(function() require("awards53.editor").mark_as_saved() end)

                --utils.info("Зміни успішно збережено в файл!")
                M.redraw()
            else
                utils.warn("Не знайдено зв'язаного буфера для збереження.")
            end
        end

        vim.api.nvim_create_autocmd("BufWriteCmd", {
            buffer = M.body_buf,
            callback = save_card_action,
        })

        vim.api.nvim_buf_create_user_command(M.body_buf, "W", save_card_action, { desc = "Зберегти картки" })

        vim.api.nvim_buf_create_user_command(M.body_buf, "Q", function(opts)
            if M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf) then
                vim.bo[M.body_buf].modified = false
            end

            if opts.bang then
                for _, b in ipairs(vim.api.nvim_list_bufs()) do
                    if vim.api.nvim_buf_is_valid(b) then vim.bo[b].modified = false end
                end
            end

            local target_win, target_buf = M.body_win, M.body_buf
            M.body_win, M.body_buf = nil, nil

            if target_win and vim.api.nvim_win_is_valid(target_win) then
                pcall(vim.api.nvim_win_close, target_win, true)
            elseif target_buf and vim.api.nvim_buf_is_valid(target_buf) then
                pcall(vim.api.nvim_buf_delete, target_buf, { force = true })
            end
        end, { bang = true })

        vim.cmd([[
            cnoreabbrev <buffer> <expr> q (getcmdtype() == ':' && bufnr('%') == ]] .. M.body_buf .. [[) ? 'Q' : 'q'
            cnoreabbrev <buffer> <expr> q! (getcmdtype() == ':' && bufnr('%') == ]] .. M.body_buf .. [[) ? 'Q!' : 'q!'
            cnoreabbrev <buffer> <expr> й (getcmdtype() == ':' && bufnr('%') == ]] .. M.body_buf .. [[) ? 'Q' : 'й'
            cnoreabbrev <buffer> <expr> й! (getcmdtype() == ':' && bufnr('%') == ]] .. M.body_buf .. [[) ? 'Q!' : 'й!'
            cnoreabbrev <buffer> <expr> w (getcmdtype() == ':' && bufnr('%') == ]] .. M.body_buf .. [[) ? 'W' : 'w'
            cnoreabbrev <buffer> <expr> w! (getcmdtype() == ':' && bufnr('%') == ]] .. M.body_buf .. [[) ? 'W' : 'w!'
            cnoreabbrev <buffer> <expr> ц (getcmdtype() == ':' && bufnr('%') == ]] .. M.body_buf .. [[) ? 'W' : 'ц'
            cnoreabbrev <buffer> <expr> ц! (getcmdtype() == ':' && bufnr('%') == ]] .. M.body_buf .. [[) ? 'W' : 'ц!'
        ]])
        
        local src_buf = state.get_source_buffer()
        if src_buf and vim.api.nvim_buf_is_valid(src_buf) then
            local group = vim.api.nvim_create_augroup("Awards53SourceSync", { clear = true })
            vim.api.nvim_create_autocmd({ "BufWritePost" }, {
                buffer = src_buf,
                group = group,
                callback = function()
                    local lines = vim.api.nvim_buf_get_lines(src_buf, 0, -1, false)
                    local parser_mod = require("awards53.parser")
                    local commands = require("awards53.commands")
                    
                    local first, last = commands.find_awards_block(lines)
                    if first then
                        local block = vim.list_slice(lines, first + 1, last)
                        local data = parser_mod.parse(block)
                        
                        local curr_rec = state.index()
                        local curr_fld = state.field_index()
                        state.set(data)
                        state.goto_record(curr_rec)
                        state.field = curr_fld

                        state.is_changed = false
                        pcall(function() require("awards53.editor").mark_as_saved() end)

                        if M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf) then
                            M.redraw()
                        end
                    end
                end,
            })
        end         

        vim.api.nvim_create_autocmd("BufWipeout", { 
            buffer = M.body_buf, 
            callback = function() 
                if state.is_changed then 
                    local org_buf = state.get_source_buffer() 
                    if org_buf and vim.api.nvim_buf_is_valid(org_buf) then 
                        state.sync_to_disk() 
                    end 
                end 
                M.body_buf, M.body_win = nil, nil 
            end, 
        }) 
    end

    M.body_win = vim.api.nvim_get_current_win() 
    vim.api.nvim_win_set_buf(M.body_win, M.body_buf) 
    vim.wo[M.body_win].statusline = "%!v:lua.require'awards53.status'.render()"
    local wo = vim.wo[M.body_win]
    wo.number, wo.relativenumber, wo.signcolumn, wo.colorcolumn = false, false, "no", "" 
    -- Перенос рядків у картці Awards53
    wo.wrap = true
    wo.linebreak = true
    M.redraw() 
end

function M.focus() 
    if M.body_win and vim.api.nvim_win_is_valid(M.body_win) then 
        vim.api.nvim_set_current_win(M.body_win) 
    end 
end 

function M.close_editor() 
    state.set_mode("NORMAL") 
    M.redraw() 
end 

return M
