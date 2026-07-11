local M = {}

local parser = require("awards53.parser")
local state = require("awards53.state")
local ui = require("awards53.ui")
local serializer = require("awards53.serializer")
local converter = require('awards53.converter')
local utils = require("awards53.utils")
local cfg = require("awards53")

-- Пошук меж блоку (повертає точні індекси рядків)
local function find_awards_block(lines)
    local start_line, finish_line
    local inside = false

    for i, line in ipairs(lines) do
        if not inside then
            if utils.is_section(line) then
                start_line = i
                inside = true
            end
        else
            if utils.is_heading(line) then
                finish_line = i - 1
                break
            end
        end
    end

    if inside and not finish_line then
        finish_line = #lines
    end

    return start_line, finish_line
end

-- Допоміжна функція для отримання лише рядків нашого блоку
local function get_awards_block_lines(buf_lines)
    local first, last = find_awards_block(buf_lines)
    if not first then return nil end
    -- Зрізаємо таблицю рядків від першої до останньої лінії включно (без заголовка секції)
    return vim.list_slice(buf_lines, first + 1, last)
end

local function open_cards()
    local current_buf = vim.api.nvim_get_current_buf()
    local target_buf = current_buf

    -- Перевіряємо, чи є в поточному буфері потрібний розділ
    local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
    local first, _ = find_awards_block(lines)

    -- Розумний пошук: якщо ми в буфері документів (де секції немає), шукаємо відкриту базу
    if not first then
        local found_base = false
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(buf) then
                local blines = vim.api.nvim_buf_get_lines(buf, 0, 100, false)
                local b_first, _ = find_awards_block(blines)
                if b_first then
                    target_buf = buf
                    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                    first = b_first
                    found_base = true
                    break
                end
            end
        end
        
        -- Якщо базу взагалі не знайдено ніде, дозволяємо ініціалізацію в поточному буфері
        if not found_base then
            first = nil
        end
    end

    state.set_source_buffer(target_buf)
    state.set_source_win(vim.api.nvim_get_current_win())

    -- Ініціалізація порожнього файлу або відсутньої секції
    if not first or (#lines == 1 and vim.trim(lines[1]) == "") then
        lines = { "*" .. " " .. cfg.config.section, "", "" }
        
        local old_mod = vim.bo[target_buf].modifiable
        vim.bo[target_buf].modifiable = true
        vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, lines)
        vim.bo[target_buf].modifiable = old_mod
        
        first = 1
    end

    local block = get_awards_block_lines(lines) or {}
    local data = parser.parse(block)

    -- Гарантуємо структуру, щоб уникнути падіння UI
    if #data.records == 0 then table.insert(data.records, { ["1"] = { "" } }) end
    if #data.headers == 0 then table.insert(data.headers, "1") end

    state.set(data)
    ui.open()
end

local function convert_buffer()
    local buf = state.get_source_buffer()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        buf = vim.api.nvim_get_current_buf()
    end

    local buf_name = vim.api.nvim_buf_get_name(buf)
    -- Розумне визначення вихідного шляху (тернарний оператор)
    local out_path = (buf_name == "") 
        and (vim.fn.expand("~") .. "/awards_output.htmp") 
        or (vim.fn.fnamemodify(buf_name, ":p:r") .. ".htmp")

    -- Створення папки, якщо її немає
    local dir = vim.fn.fnamemodify(out_path, ":p:h")
    if vim.fn.isdirectory(dir) == 0 then vim.fn.mkdir(dir, "p") end

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local block = get_awards_block_lines(lines)

    if not block or #block == 0 then
        utils.warn("Секцію " .. cfg.config.section .. " не знайдено!")
        return
    end

    local data = parser.parse(block, cfg.config.separator)
    local html_table = converter.html(data)
    local clean_lines = vim.split(html_table, "\n", { trimempty = false })

    -- Безпечний запис
    local success, err = pcall(vim.fn.writefile, clean_lines, out_path)
    if success then
        utils.info("Файл успішно збережено за абсолютним шляхом:\n" .. out_path)
    else
        utils.error("Помилка запису файлу: " .. tostring(err))
    end
end

function M.sync_org_buffer()
    local buf = state.get_source_buffer()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local first, last = find_awards_block(lines)

    if not first then
        utils.error("Розділ " .. cfg.config.section .. " не знайдено")
        return
    end
    local out = serializer.build(state.data())

    -- Тимчасово розблоковуємо буфер перед записом ліній
    local old_modifiable = vim.bo[buf].modifiable
    vim.bo[buf].modifiable = true
    
    vim.api.nvim_buf_set_lines(buf, first, last, false, out)
    
    vim.bo[buf].modifiable = old_modifiable
end

local function save_cards()
    M.sync_org_buffer() 

    local buf = state.get_source_buffer()
    if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_call(buf, function()
            vim.cmd("write")
        end)
    end
end

-- 
function M.setup()
    local commands = {
        Awards53Convert = convert_buffer,
        Awards53 = open_cards,
        Awards53abbr = function() 
            require("awards53.abbreviations").edit_config() 
        end,
    }
    
    -- реєстрація команд через цикл
    for cmd_name, callback in pairs(commands) do
        vim.api.nvim_create_user_command(cmd_name, callback, {})
    end
end


return M
