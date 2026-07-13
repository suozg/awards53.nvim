local M = {}

local header = require("awards53.header") --
local body = require("awards53.body") --
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

function M.redraw() 
    if not (M.body_buf and vim.api.nvim_buf_is_valid(M.body_buf)) then return end 

    vim.bo[M.body_buf].modifiable = true 
    vim.api.nvim_buf_set_lines(M.body_buf, 0, -1, false, render_body()) 
    vim.bo[M.body_buf].modifiable = false 
  
    utils.highlight_rnokpp_in_buf(M.body_buf) 
    apply_field_highlighting(M.body_buf) 
end

local ua = { 
    h = "р", j = "о", k = "л", l = "д", i = "ш", a = "ф", s = "і", d = "в", f = "а", g = "п", y = "н", u = "г", n = "т", p = "з", 
    H = "Р", J = "О", K = "Л", L = "Д", I = "Ш", A = "Ф", S = "І", D = "В", F = "А", G = "П", Y = "Н", U = "Г", N = "Т", P = "З", 
    ["["] = "х", ["]"] = "ї", ["/"] = ".", ["?"] = ",", 
} 

local function translate_to_uk(str) 
    if str:match("<.*>") or str:match("^:") then return str end 
    local result = "" 
    for i = 1, #str do 
        local char = str:sub(i, i) 
        result = result .. (ua[char] or char) 
    end 
    return result 
end

local function bind_keys()
    local cfg = require("awards53") 
    local actions = require("awards53.actions") 

    local keymaps = {
        ["h"]   = { function() return state.prev() end, true },
        ["l"]   = { function() return state.next() end, true },
        ["[["]  = { function() state.first() end, true },
        ["]]"]  = { function() state.last() end, true },
        ["<H>"] = { function() state.jump(5) end, true },
        ["<L>"] = { function() state.jump(-5) end, true },
        
        ["s"]   = { function() if vim.v.count > 0 then return state.goto_record(vim.v.count) end end, true },
        ["S"]   = { function() state.sort_by(cfg.config.default_sort) state.first() end, true },
        
        ["j"]   = { function() 
            state.field = state.field_index() < #state.headers_list() and state.field_index() + 1 or 1
            state.last_field = state.field
        end, true },
        
        ["k"]   = { function() 
            state.field = state.field_index() > 1 and state.field_index() - 1 or #state.headers_list()
            state.last_field = state.field
        end, true },
        -- Зсув тексту полів у поточній картці (Shift+j / k)
        ["J"] = { function() return state.move_field_content_down() end, true },
        ["K"] = { function() return state.move_field_content_up() end, true },
         -- Зсув тексту полів у поточній картці (Leader+j / k)
        ["<leader>j"] = { function() return state.move_field_globally_down() end, true },
        ["<leader>k"] = { function() return state.move_field_globally_up() end, true },
        
        ["i"]   = { function() state.set_mode("INSERT") M.redraw() editor.open() end, false },
        ["A"]   = { function() state.new_record() M.redraw() state.set_mode("INSERT") M.redraw() editor.open() end, false },
        
        ["F"]   = { function() if state.new_field() then M.redraw() utils.info("Додано нове поле №" .. state.field_name()) end end, false },
        ["F-"]   = { function() if state.new_field("-") then M.redraw() utils.info("Додано нове поле №" .. state.field_name() .. "із '-'") end end, false },
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
        
        ["g/"]   = { function() 
            vim.ui.select(state.headers_list(), { prompt = "🔍 Шукати в полі:" }, function(f)
                if f then vim.ui.input({ prompt = "Пошук (" .. f .. "): " }, function(t) if t and t ~= "" then state.find(t, 1, f) M.redraw() end end) end
            end)
        end, false },

        ["n"]   = { function() return state.find_next() end, true },
        ["N"]   = { function() return state.find_next(-1) end, true },
        -- схлопування пустих полів по всьому файлу
        ["0"] = { function() return state.collapse_empty_fields_globally() end, true },
        -- Екшени з actions.lua
        ["O"]   = { function() actions.sort_officers_first() state.first() end, true },
        ["R"]   = { function() actions.format_rnokpp_in_current_card() end, true },
        ["X"]   = { function() actions.format_rnokpp_in_all_cards() end, true },
        -- Заміна переносів рядків на пробіли
        ["e"] = { function() return state.flatten_current_field() end, true },
        ["E"] = { function() return state.flatten_field_globally() end, true },

        ["?"] = { function() require("awards53.help").open() end, false  },
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
        local uk = translate_to_uk(lhs) 
        if uk ~= lhs then vim.keymap.set("n", uk, handler, opts) end 
    end
end

---------------------------------------------------------
function M.open()
    vim.cmd("highlight default link Awards53ActiveField CursorLine") 
    M.body_buf = vim.api.nvim_create_buf(false, true) 

    vim.bo[M.body_buf].buftype = "nofile" 
    vim.bo[M.body_buf].bufhidden = "wipe" 
    vim.bo[M.body_buf].swapfile = false 

    vim.cmd("tabnew") 
    M.body_win = vim.api.nvim_get_current_win() 
    vim.api.nvim_win_set_buf(M.body_win, M.body_buf) 

    vim.api.nvim_create_autocmd("BufWipeout", { 
        buffer = M.body_buf, 
        callback = function() 
            if state.is_changed then
                local org_buf = state.get_source_buffer()
                if org_buf and vim.api.nvim_buf_is_valid(org_buf) then
                    -- Викликаємо безпосередньо Lua-функцію синхронізації всередині pcall
                    local success = pcall(state.sync_to_disk)
                    if success then 
                        vim.bo[org_buf].modified = true
                    else 
                        utils.warn("Не вдалося синхронізувати зміни.")
                    end 
                end
            end
            M.body_buf, M.body_win = nil, nil 
        end, 
    }) 

    vim.api.nvim_buf_set_name(M.body_buf, "Awards53") 
    vim.wo[M.body_win].statusline = "%!v:lua.require'awards53.status'.render()" 

    local wo = vim.wo[M.body_win]
    wo.number, wo.relativenumber, wo.signcolumn, wo.colorcolumn = false, false, "no", "" 

    bind_keys() 
    vim.keymap.set("n", ":w<CR>", ":q<CR>", { buffer = M.body_buf, silent = true }) 
    M.redraw() 
end

function M.focus()
    if M.body_win and vim.api.nvim_win_is_valid(M.body_win) then vim.api.nvim_set_current_win(M.body_win) end 
end

function M.close_editor()
    state.set_mode("NORMAL") 
    M.redraw() 
    M.focus() 
end

return M 
