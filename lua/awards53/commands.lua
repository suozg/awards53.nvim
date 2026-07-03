local M = {}

local parser = require("awards53.parser")
local state = require("awards53.state")
local ui = require("awards53.ui")
local serializer = require("awards53.serializer")

local function find_awards_block(lines)

    local start_line
    local finish_line

    local inside = false

    for i, line in ipairs(lines) do

        if not inside then

            if line:match("^%*+%s+AWARDS53%s*$") then
                start_line = i
                inside = true
            end

        else

            if line:match("^%*+%s+") then
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

        if line:match("^%*+%s+AWARDS53%s*$") then

            inside = true

        elseif inside and line:match("^%*+%s+") then

            break

        elseif inside then

            table.insert(block, line)

        end
    end

    local data = parser.parse(block)

    if #data.records == 0 then
        vim.notify("У розділі AWARDS53 немає записів", vim.log.levels.WARN)
        return
    end

    state.set(data)
    ui.open()

end


local function convert_buffer()

    local buf = vim.api.nvim_get_current_buf()
    
    -- Отримуємо повний шлях до поточного файлу в буфері
    local buf_name = vim.api.nvim_buf_get_name(buf)
    
    -- Якщо файл ще ніде не збережений (новий буфер), збережемо його в tmp
    local out_path
    if buf_name == "" then
        out_path = vim.fn.tempname() .. ".html"
    else
        -- Міняємо розширення оригінального файлу (.org або будь-яке інше) на .html
        out_path = vim.fn.fnamemodify(buf_name, ":r") .. ".htmp"
    end

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local out = {}

    local inside = false
    local block = {}

    for _, line in ipairs(lines) do

        -- Начало раздела
        if line:match("^%*+%s+AWARDS53%s*$") then
            inside = true
            block = {}

        -- Следующий заголовок Org
        elseif inside and line:match("^%*+%s+") then
            inside = false

            local data = parser.parse(block)
            table.insert(out, writer.html(data))

            -- сам новый заголовок не теряем
            table.insert(out, line)

        elseif inside then
            table.insert(block, line)

        else
            table.insert(out, line)
        end
    end

    -- Если AWARDS53 был последним разделом файла
    if inside then
        local data = parser.parse(block)
        table.insert(out, writer.html(data))
    end

    -- Зклеюємо в один текст і ріжемо на чисті рядки, щоб уникнути нуль-байтів (@)
    local final_text = table.concat(out, "\n")
    local clean_lines = vim.split(final_text, "\n", { trimempty = false })

    -- Записуємо файл поруч з оригіналом
    vim.fn.writefile(clean_lines, out_path)

    print("Written: " .. out_path)
end


local function save_cards()

    local buf = state.get_source_buffer()
    local lines = vim.api.nvim_buf_get_lines(
        buf,
        0,
        -1,
        false
    )

    local first, last = find_awards_block(lines)

    if not first then
        vim.notify(
            "Розділ AWARDS53 не знайдено",
            vim.log.levels.ERROR
        )
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

    vim.notify(
        "Картки збережено",
        vim.log.levels.INFO
    )
   
    local win = state.get_source_win()

    if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
    end

    if ui.win and vim.api.nvim_win_is_valid(ui.win) then
        vim.api.nvim_win_close(ui.win, true)
    end

    vim.bo[buf].modified = true

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

end

return M
