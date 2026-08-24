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

vim.cmd("highlight default link Awards53ActiveField CursorLine")


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

function M.redraw() 
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
                pcall(state.sync_to_disk) 
                M.redraw() utils.info("Поле видалено") 
            else utils.error("Не вдалося видалити поле") end 
        end, false }, 

        ["dd"]  = { function() 
            state.copy_current() 
            if state.delete_current() then utils.info("Картку вирізано") else utils.error("Не можна видалити останню картку") end 
        end, true }, 
        
        ["yy"]  = { function() state.copy_current() utils.info("Картку скопійовано") end, false }, 
        ["p"]   = { function() return state.paste_after() end, true }, 
        ["u"]   = { function() return state.undo_last() end, true }, 
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
                pcall(state.sync_to_disk)

                if vim.bo[src_buf].modified then
                    vim.api.nvim_buf_call(src_buf, function()
                        vim.cmd("silent! write")
                    end)
                end

                state.is_changed = false
                pcall(function() require("awards53.editor").mark_as_saved() end)

                utils.info("Зміни успішно збережено в файл!")
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
                        pcall(state.sync_to_disk) 
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
