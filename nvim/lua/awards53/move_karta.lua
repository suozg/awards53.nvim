local M = {}

local state = require("awards53.state")
local utils = require("awards53.utils")
local parser = require("awards53.parser")
local serializer = require("awards53.serializer")
local cfg = require("awards53")

function M.move_to_fork()
    -- 1. Отримуємо поточну картку
    local current_card = state.current_record()
    if not current_card then
        utils.warn("Немає активної картки для переміщення!")
        return
    end

    -- Глибока копія картки
    local card_to_move = vim.deepcopy(current_card)
    -- Отримуємо ПОВНИЙ список заголовків полів з поточного файлу (наприклад, {"1", "2", "3", ...})
    local current_headers = vim.deepcopy(state.headers_list())

    -- 2. Отримуємо джерельний буфер та його шлях
    local src_buf = state.get_source_buffer()
    if not src_buf or not vim.api.nvim_buf_is_valid(src_buf) then
        utils.error("Не знайдено джерельний .org буфер!")
        return
    end

    local current_file_path = vim.api.nvim_buf_get_name(src_buf)
    if not current_file_path or current_file_path == "" then
        utils.error("Поточний буфер не має збереженого шляху до файлу на диску!")
        return
    end

    -- Визначаємо шлях до проблема-файлу у тому ж каталозі
    local dir = vim.fn.fnamemodify(current_file_path, ":h")
    local fork_path = dir .. "/fork.org"

    -- 3. Читаємо або створюємо fork.org
    local target_lines = {}
    local file_exists = vim.fn.filereadable(fork_path) == 1

    if file_exists then
        target_lines = vim.fn.readfile(fork_path)
    else
        target_lines = { "*" .. " " .. cfg.config.section, "", "" }
    end

    -- 4. Парсимо вміст проблема-файла
    local commands = require("awards53.commands")
    local first, last = commands.find_awards_block(target_lines)

    local target_block = {}
    if first then
        target_block = vim.list_slice(target_lines, first + 1, last)
    end

    local target_data = parser.parse(target_block)

    -- 💥 КЛЮЧОВЕ ВИПРАВЛЕННЯ:
    -- Якщо target_data не має заголовків або вони неповні — об'єднуємо їх із заголовками нашої картки
    if #target_data.headers == 0 then
        target_data.headers = current_headers
    else
        -- Об'єднуємо заголовки, щоб не втратити поля, якщо в проблема-файлі їх було менше
        local existing_headers_map = {}
        for _, h in ipairs(target_data.headers) do
            existing_headers_map[h] = true
        end
        for _, h in ipairs(current_headers) do
            if not existing_headers_map[h] then
                table.insert(target_data.headers, h)
            end
        end
    end

    -- Вставляємо повну картку
    table.insert(target_data.records, card_to_move)

    -- 5. Серіалізуємо та записуємо в fork.org
    local new_block_lines = serializer.build(target_data)

    if first then
        local before = vim.list_slice(target_lines, 1, first)
        local after = (last < #target_lines) and vim.list_slice(target_lines, last + 1, #target_lines) or {}
        
        target_lines = {}
        vim.list_extend(target_lines, before)
        vim.list_extend(target_lines, new_block_lines)
        vim.list_extend(target_lines, after)
    else
        vim.list_extend(target_lines, new_block_lines)
    end

    vim.fn.writefile(target_lines, fork_path)

    -- 6. Видаляємо картку з поточного стану та зберігаємо основний файл
    if not state.delete_current() then
        utils.error("Не вдалося видалити картку з поточного списку")
        return
    end

    state.sync_to_disk()

    vim.api.nvim_buf_call(src_buf, function()
        pcall(vim.cmd, "silent write!")
    end)

    utils.info("Картку з усіма полями успішно переміщено в fork.org!")
end

return M
