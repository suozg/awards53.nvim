local M = {}

local parser = require("awards53.parser")
local state = require("awards53.state")
local ui = require("awards53.ui")
local serializer = require("awards53.serializer")
local converter = require('awards53.converter')
local utils = require("awards53.utils")
local cfg = require("awards53")


local function find_awards_block(lines)

    local start_line
    local finish_line
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


local function open_cards()

    local buf = vim.api.nvim_get_current_buf()
    
    state.set_source_buffer(buf)
    state.set_source_win(vim.api.nvim_get_current_win())
    
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local inside = false
    local block = {}

    for _, line in ipairs(lines) do

        if utils.is_section(line) then

            inside = true

        elseif inside and utils.is_heading(line) then

            break

        elseif inside then

            table.insert(block, line)

        end
    end

    local data = parser.parse(block)

    if #data.records == 0 then
        utils.warn("У розділі " .. cfg.config.section .. " немає записів")
        return
    end

    state.set(data)
    ui.open()

end


local function convert_buffer()
    -- 1. Отримуємо буфер оригінального .org файлу
    local buf = state.get_source_buffer()
    
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        buf = vim.api.nvim_get_current_buf()
    end

    local buf_name = vim.api.nvim_buf_get_name(buf)
    
    local out_path
    if buf_name == "" then
        -- Якщо файл ще не збережений на диску, пишемо в тимчасову папку ОС
        out_path = vim.fn.expand("~") .. "/awards_output.htmp"
    else
        -- Абсолютний шлях до файлу без розширення + .htmp
        out_path = vim.fn.fnamemodify(buf_name, ":p:r") .. ".htmp"
    end

    -- Переконуємось, що папка для запису існує (якщо ні — створюємо її)
    local dir = vim.fn.fnamemodify(out_path, ":p:h")
    if vim.fn.isdirectory(dir) == 0 then
        vim.fn.mkdir(dir, "p")
    end

    -- 2. Зчитуємо сирий файл
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local out = {}
    local inside = false
    local block = {}

    for _, line in ipairs(lines) do
        if utils.is_section(line) then
            inside = true
            block = {}
        elseif inside and utils.is_heading(line) then
            inside = false
            break 
        elseif inside then
            table.insert(block, line)
        end
    end

    -- 3. Парсимо та конвертуємо
    if #block > 0 then
        -- Передаємо правильний сепаратор з конфігурації
        local data = parser.parse(block, cfg.config.separator)
        local html_table = converter.html(data)
        table.insert(out, html_table)
    else
        utils.warn("Секцію " .. cfg.config.section .. " нне знайдено!")
        return
    end

    local final_text = table.concat(out, "\n")
    local clean_lines = vim.split(final_text, "\n", { trimempty = false })

    -- 4. Безпечний запис на диск
    local success, err = pcall(function()
        vim.fn.writefile(clean_lines, out_path)
    end)

    if success then
        utils.info("Файл успішно збережено за абсолютним шляхом:\n" .. out_path)
    else
        utils.error("Помилка запису файлу: " .. tostring(err))
    end
end


local function sync_org_buffer()
    
    local rec = state.current_record()
    local buf = state.get_source_buffer()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    local first, last = find_awards_block(lines)

    if not first then
        utils.error("Розділ " .. cfg.config.section .. " не знайдено")
        return
    end
    local out = serializer.build(state.data())

    vim.api.nvim_buf_set_lines(
        buf,
        first,
        last,
        false,
        out
    )

end


local function save_cards()

    sync_org_buffer()

    local buf = state.get_source_buffer()

    vim.api.nvim_buf_call(buf, function()
        vim.cmd("write")
    end)

end


function M.setup()

    vim.api.nvim_create_user_command(
        "Awards53Convert",
        convert_buffer,
        {}
    )

    vim.api.nvim_create_user_command(
        "Awards53",
        open_cards,
        {}
    )

    vim.api.nvim_create_user_command(

        "Awards53Save",

        save_cards,

        {}

    )
    vim.api.nvim_create_user_command(
        "Awards53Sync",
        sync_org_buffer,
        {}
    )

end

return M
