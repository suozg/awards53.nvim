local M = {}

local header = require("awards53.header") 
local body = require("awards53.body") 
local state = require("awards53.state") 
local editor = require("awards53.editor") 
local utils = require("awards53.utils") 

M.body_buf = nil 
M.body_win = nil 

local NS_ID = vim.api.nvim_create_namespace("awards53_fields") 
local syntax_group = "Awards53ActiveField" 

local function apply_field_highlighting(buf) 
    vim.api.nvim_buf_clear_namespace(buf, NS_ID, 0, -1) 
    vim.api.nvim_buf_call(buf, function() 
        vim.cmd("syntax clear " .. syntax_group) 
        vim.cmd([[syntax match ]] .. syntax_group .. [[ /^\s\s.*/]]) 
    end) 
end

local function render_body() 
    local lines = {} 
    vim.list_extend(lines, header.render()) 
    vim.list_extend(lines, body.render()) 
    return lines 
end

-- Оновлення назви буфера картки для mini.tabline (із зірочкою *, якщо є зміни)
local function update_ui_buffer_title()
    if not (M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf)) then return end

    local src_buf = state.get_source_buffer()
    local is_modified = state.is_changed

    if src_buf and vim.api.nvim_buf_is_valid(src_buf) and vim.bo[src_buf].modified then
        is_modified = true
    end

    local title = is_modified and "* Awards53" or "Awards53"
    pcall(vim.api.nvim_buf_set_name, M.body_buf, title)
end

function M.render_status()
    local src_buf = state.get_source_buffer()
    local is_modified = state.is_changed
    
    if src_buf and vim.api.nvim_buf_is_valid(src_buf) and vim.bo[src_buf].modified then
        is_modified = true
    end

    local mod_flag = is_modified and " [+] " or " "
    local rec_idx = state.index()
    local rec_cnt = state.count()
    local f_name = state.field_name()

    return string.format(
        " КАРТКА %d/%d%s│ Поле: %s │ <i/ENTER> редагувати │ <Tab> навігація",
        rec_idx, rec_cnt, mod_flag, f_name
    )
end

function M.redraw() 
    if not (M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf)) then return end 

    vim.bo[M.body_buf].modifiable = true 
    vim.api.nvim_buf_set_lines(M.body_buf, 0, -1, false, render_body()) 
    vim.bo[M.body_buf].modifiable = false 
  
    utils.highlight_rnokpp_in_buf(M.body_buf) 
    apply_field_highlighting(M.body_buf) 

    if M.body_win and vim.api.nvim_win_is_valid(M.body_win) then
        if vim.api.nvim_get_current_win() == M.body_win then
            vim.api.nvim_win_set_cursor(M.body_win, { 1, 0 })
        end
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
        
        ["s"]   = { function() if vim.v.count > 0 then return state.goto_record(vim.v.count) end end, true }, 
        ["S"]   = { function() state.sort_by(cfg.config.default_sort) state.first() end, true }, 
        
        ["j"]   = { function() return state.next_field() end, true },
        ["k"]   = { function() return state.prev_field() end, true },

        ["J"]   = { function() return state.move_field_content_down() end, true }, 
        ["K"]   = { function() return state.move_field_content_up() end, true }, 
        ["<leader>j"] = { function() return state.move_field_globally_down() end, true }, 
        ["<leader>k"] = { function() return state.move_field_globally_up() end, true }, 
        
        ["i"]   = { function() state.set_mode("INSERT") M.redraw() editor.open() end, false }, 
        ["A"]   = { function() state.new_record() M.redraw() state.set_mode("INSERT") M.redraw() editor.open() end, false }, 
        
        ["F"]   = { function() if state.new_field() then M.redraw() utils.info("Додано нове поле №" .. state.field_name()) end end, false }, 
        ["F-"]  = { function() if state.new_field("-") then M.redraw() utils.info("Додано нове поле №" .. state.field_name() .. " із '-'") end end, false }, 
        ["B"]   = { function() 
            if state.delete_field() then 
                pcall(state.sync_to_disk) 
                M.redraw() utils.info("Поле успішно видалено") 
            else utils.error("Не вдалося видалити поле") end 
        end, false }, 

        ["dd"]  = { function() 
            state.copy_current() 
            if state.delete_current() then utils.info("Картку вирізано") else utils.error("Не можна видалити останню картку") end 
        end, true }, 
        
        ["yy"]  = { function() state.copy_current() utils.info("Картку скопійовано") end, false }, 
        ["p"]   = { function() return state.paste_after() end, true }, 
        ["u"]   = { function() return state.undo_last() end, true }, 

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

        ["?"]   = { function() require("awards53.help").open() end, false  }, 
    }

    local opts = { buffer = M.body_buf, silent = true } 
    for lhs, action_data in pairs(keymaps) do 
        local func, need_redraw = action_data[1], action_data[2] 
        local handler = function() 
            local res = func() 
            if need_redraw and res ~= false then 
                M.redraw() 
            end 
        end 
        vim.keymap.set("n", lhs, handler, opts) 
        
        local uk = utils.translate_key(lhs) 
        if uk ~= lhs then 
            vim.keymap.set("n", uk, handler, opts) 
        end 
    end
end

function M.open() 
    vim.cmd("highlight default link Awards53ActiveField CursorLine") 

    -- Створюємо перелічувальний буфер карток (buflisted = true)
    if not (M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf)) then
        M.body_buf = vim.api.nvim_create_buf(true, false) 
        
        vim.bo[M.body_buf].buftype = "nofile" 
        vim.bo[M.body_buf].bufhidden = "hide" -- Не знищувати при перемиканні буферів!
        vim.bo[M.body_buf].swapfile = false 
        
        update_ui_buffer_title()

        local keys_to_disable = { 
            "<Up>", "<Down>", "<Left>", "<Right>", 
            "w", "b", "ge", "$", "^", "gg", "G" 
        }
        for _, key in ipairs(keys_to_disable) do
            vim.keymap.set("n", key, "<Nop>", { buffer = M.body_buf, noremap = true, silent = true })
        end

        bind_keys()
        
        -- Власна команда закриття картки для перехоплення незбережених правок у ВСІХ буферах
        vim.api.nvim_buf_create_user_command(M.body_buf, "Q", function(opts)
            local editor = require("awards53.editor")
            -- Якщо вихід примусовий (:q!), скидаємо прапори модифікації у всіх фонових буферах
            if opts.bang then
                for _, b in ipairs(vim.api.nvim_list_bufs()) do
                    if vim.api.nvim_buf_is_valid(b) then
                        vim.bo[b].modified = false
                    end
                end
            end

            if M.body_win and vim.api.nvim_win_is_valid(M.body_win) then
                pcall(vim.api.nvim_win_close, M.body_win, true)
            end
        end, { bang = true })

        vim.cmd("cnoreabbrev <buffer> q Q")
        vim.cmd("cnoreabbrev <buffer> q! Q!")
        vim.cmd("cnoreabbrev <buffer> й Q")
        vim.cmd("cnoreabbrev <buffer> й! Q!")

        -- Автоматичне оновлення стан-бази, якщо користувач відредагував .org файл напряму
        local src_buf = state.get_source_buffer()
        if src_buf and vim.api.nvim_buf_is_valid(src_buf) then
            local group = vim.api.nvim_create_augroup("Awards53SourceSync", { clear = true })
            
            vim.api.nvim_create_autocmd({ "BufWritePost", "TextChanged" }, {
                buffer = src_buf,
                group = group,
                callback = function()
                    local lines = vim.api.nvim_buf_get_lines(src_buf, 0, -1, false)
                    local parser = require("awards53.parser")
                    local commands = require("awards53.commands")
                    
                    local first, last = commands.find_awards_block(lines)
                    if first then
                        local block = vim.list_slice(lines, first + 1, last)
                        local data = parser.parse(block)
                        -- Зберігаємо позицію перед оновленням
                        local curr_rec = state.index()
                        local curr_fld = state.field_index()
                        state.set(data)
                        -- Відновлюємо позицію
                        state.goto_record(curr_rec)
                        state.field = curr_fld
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

    -- Відкриваємо буфер у поточному вікні
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
    M.focus() 
end 

return M
