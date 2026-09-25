-- init.lua (Головний модуль ініціалізації плагіна awards53)
local config = require("awards53.config")
local M = {}
local uv = vim.uv or vim.loop
M.config = config.options

local defaults = {
    separator = "::",
    section = "AWARDS53",
    default_sort = "1",
    record_separator = "===",
}

M.config = {}

-- Перевірка, чи живий процес за його PID
local function is_process_running(pid)
    if not pid or pid <= 0 then return false end
    -- uv.kill(pid, 0) повертає 0 (або true), якщо процес існує та належить користувачу
    local code = uv.kill(pid, 0)
    return code == 0
end

-- Атомарне створення lock-файлу
local function acquire_lock(file_path)
    if not file_path or file_path == "" then return true end
    local lock_path = file_path .. ".awards53.lock"
    local current_pid = vim.fn.getpid()

    -- Прапорці: O_CREAT (створити) + O_EXCL (впасти, якщо вже існує) + O_WRONLY (запис)
    local flags = bit.bor(uv.constants.O_CREAT, uv.constants.O_EXCL, uv.constants.O_WRONLY)
    -- Права доступу: 0644 (rw-r--r--)
    local mode = 420 

    local fd = uv.fs_open(lock_path, flags, mode)

    if fd then
        -- Файл успішно створено атомарно! Записуємо PID
        uv.fs_write(fd, tostring(current_pid), -1)
        uv.fs_close(fd)
        return true, lock_path
    end

    -- Якщо fd == nil, файл вже існує. Перевіряємо, чи живий процес-власник (Stale lock check)
    local read_fd = uv.fs_open(lock_path, "r", 438)
    if read_fd then
        local stat = uv.fs_fstat(read_fd)
        local data = ""
        if stat and stat.size > 0 then
            data = uv.fs_read(read_fd, stat.size, 0) or ""
        end
        uv.fs_close(read_fd)

        local owner_pid = tonumber(vim.trim(data))

        -- Якщо PID не зчитується або процес МЕРТВИЙ — це stale lock, видаляємо його і пробуємо знову
        if owner_pid and not is_process_running(owner_pid) then
            vim.notify("Виявлено застарілий lock-файл (процес " .. owner_pid .. " завершився). Перехоплюємо лок...", vim.log.levels.WARN)
            os.remove(lock_path)
            
            -- Повторна спроба після очищення
            local retry_fd = uv.fs_open(lock_path, flags, mode)
            if retry_fd then
                uv.fs_write(retry_fd, tostring(current_pid), -1)
                uv.fs_close(retry_fd)
                return true, lock_path
            end
        end
    end

    return false, lock_path
end

-- Видалення lock-файлу
function M.release_lock(file_path)
    if not file_path or file_path == "" then return end
    local lock_path = file_path .. ".awards53.lock"
    os.remove(lock_path)
end

function M.setup(opts)
    local utils = require("awards53.utils")
    local state = require("awards53.state")

    config.setup(opts)
    M.config = config.options
    local augroup = vim.api.nvim_create_augroup("Awards53", { clear = true })

    -- 1. Namespace & Highlights
    M.ns_help = vim.api.nvim_create_namespace("awards53_editor_help")
    M.ns_fields = vim.api.nvim_create_namespace("awards53_fields")
    M.ns_rnokpp = vim.api.nvim_create_namespace("awards53_rnokpp")

    local function setup_highlights()
        vim.cmd("highlight default link Awards53ActiveField CursorLine")
        vim.api.nvim_set_hl(0, "Awards53Help", { fg = "#897d6d", bg = "NONE" })
        vim.api.nvim_set_hl(0, "Awards53HelpText", { fg = "#897d6d", bg = "NONE", bold = false })
        vim.api.nvim_set_hl(0, "Awards53RnokppError", { link = "SpellBad", default = true })
        vim.api.nvim_set_hl(0, "Awards53ActiveFieldPrefix", { fg = "#ffffff", bg = "#739313", bold = true })
        vim.api.nvim_set_hl(0, "Awards53HiddenCursor", { blend = 100, nocombine = true })
        vim.api.nvim_set_hl(0, "Awards53ActiveFieldSeparator", { fg = "#739313" })
        vim.api.nvim_set_hl(0, "Awards53ChangedIndicator", { fg = "#b13337", bold = true })
        vim.api.nvim_set_hl(0, "Awards53Separator", { link = "Comment", default = true })
        
        local hl = vim.api.nvim_get_hl(0, { name = "CursorLine", link = false })
        local bg_color = hl.bg and string.format("#%06x", hl.bg) or "NONE"

        vim.api.nvim_set_hl(0, "Awards53ActiveFieldSuffix", { fg = bg_color, bg = "NONE" })
        vim.api.nvim_set_hl(0, "Awards53ChangedIndicatorKarta", { fg = "#b13337", bg = bg_color, bold = true })
    end

    setup_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", { group = augroup, pattern = "*", callback = setup_highlights })

    -- 2. Команди
    require("awards53.commands").setup()

    pcall(vim.api.nvim_del_user_command, "Documents53")
    vim.api.nvim_create_user_command("Documents53", function()
        local status, doc_init = pcall(require, "awards53.documents.init")
        if status and doc_init and doc_init.open then
            doc_init.open()
        else
            require("awards53.documents.converter").convert_current()
        end
    end, { desc = "Головне меню / робота з Documents53" })

    -- 3. Автокоманда відкриття
    vim.api.nvim_create_autocmd("BufReadPost", {
        group = augroup,
        callback = function(args)
            vim.schedule(function()
                if not vim.api.nvim_buf_is_valid(args.buf) then return end

                local lines = vim.api.nvim_buf_get_lines(args.buf, 0, 15, false)
                if #lines == 0 then return end

                local file_path = vim.api.nvim_buf_get_name(args.buf)

                -- Сценарій А: Виявлено заголовок AWARDS53
                if lines[1] and utils.is_section(lines[1]) then
                    
                    -- Спочатку перевіряємо внутрішній стан плагіна
                    if state.is_busy() then return end

                    -- Тільки після цього намагаємося взяти атомарний Lock
                    local success, lock_path = acquire_lock(file_path)
                    if not success then
                        vim.notify(
                            "⛔ Файл заблоковано активним процесом Neovim!\nLock-файл: " .. lock_path,
                            vim.log.levels.ERROR
                        )
                        vim.cmd("b #")
                        return
                    end

                    -- Реєструємо гарантоване видалення локу при закритті
                    local cleanup_grp = vim.api.nvim_create_augroup("Awards53LockCleanup_" .. args.buf, { clear = true })
                    vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout", "BufDelete", "VimLeavePre" }, {
                        group = cleanup_grp,
                        buffer = args.buf,
                        once = true,
                        callback = function()
                            M.release_lock(file_path)
                        end,
                    })

                    local all_lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
                    local count = 0

                    for _, line in ipairs(all_lines) do
                        if utils.is_section(line) then count = count + 1 end
                    end

                    if count > 1 then
                        vim.notify("Невірна структура даних - декілька входжень AWARDS53!", vim.log.levels.ERROR)
                        local choice = vim.fn.input("Виправити структуру даних? [1-так, 2-ні]: ")

                        if choice == "1" then
                            local found_first = false
                            for i, line in ipairs(all_lines) do
                                if utils.is_section(line) then
                                    if not found_first then
                                        found_first = true
                                    else
                                        all_lines[i] = "==="
                                    end
                                end
                            end

                            vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, all_lines)
                            vim.cmd("redraw")
                            vim.notify("Структуру виправлено (зайві заголовки замінено на ===)", vim.log.levels.INFO)
                        elseif choice == "2" then
                            -- ВАЖЛИВО: Очищаємо lock при ранньому виході!
                            M.release_lock(file_path)
                            vim.cmd("b #")
                            return
                        end
                    end

                    vim.api.nvim_set_current_buf(args.buf)
                    vim.cmd("Awards53")

                    pcall(vim.api.nvim_buf_del_user_command, args.buf, "Document53Convert")
                    vim.api.nvim_buf_create_user_command(args.buf, "Document53Convert", function()
                        require("awards53.documents.converter").convert_current()
                    end, { desc = "Конвертувати поточний документ/картку" })

                    local headers = state.headers_list()
                    if #headers > 0 and M.config.default_sort == "" then
                        M.config.default_sort = headers[1]
                    end

                    return
                end

                -- Сценарій Б: Документ DOC53
                local is_doc53 = false
                for _, line in ipairs(lines) do
                    if line:match("^#%+ODT_STYLES_FILE:") or line:match("^#%+DOC53_REQUIRED:") then
                        is_doc53 = true
                        break
                    end
                end

                if is_doc53 then
                    pcall(function() require("awards53.documents.editor").protect_tech_lines(args.buf) end)
                    pcall(function() require("awards53.abbreviations").register_buffer_abbreviations(args.buf) end)

                    pcall(vim.api.nvim_buf_del_user_command, args.buf, "Document53Convert")
                    vim.api.nvim_buf_create_user_command(args.buf, "Document53Convert", function()
                        require("awards53.documents.converter").convert_current()
                    end, { desc = "Конвертувати поточний документ/картку" })
                end
            end)
        end,
    })
end

return M
