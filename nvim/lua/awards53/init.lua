-- init.lua (Головний модуль ініціалізації плагіна awards53)
local config = require("awards53.config")
local M = {}
local uv = vim.uv or vim.loop
M.config = config.options

local function is_process_running(pid)
    return pid and pid > 0 and uv.kill(pid, 0) == 0
end

local function acquire_lock(file_path)
    if not file_path or file_path == "" then return true end
    local lock_path = file_path .. ".awards53.lock"
    local current_pid = vim.fn.getpid()
    local flags = bit.bor(uv.constants.O_CREAT, uv.constants.O_EXCL, uv.constants.O_WRONLY)
    local mode = 420 -- 0644

    local fd = uv.fs_open(lock_path, flags, mode)
    if fd then
        uv.fs_write(fd, tostring(current_pid), -1)
        uv.fs_close(fd)
        return true, lock_path
    end

    local read_fd = uv.fs_open(lock_path, "r", 438)
    if read_fd then
        local stat = uv.fs_fstat(read_fd)
        local data = (stat and stat.size > 0) and (uv.fs_read(read_fd, stat.size, 0) or "") or ""
        uv.fs_close(read_fd)

        local owner_pid = tonumber(vim.trim(data))
        if owner_pid and not is_process_running(owner_pid) then
            vim.notify("Виявлено застарілий lock-файл (процес " .. owner_pid .. " завершився). Перехоплюємо лок...", vim.log.levels.WARN)
            os.remove(lock_path)
            
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

function M.release_lock(file_path)
    if file_path and file_path ~= "" then os.remove(file_path .. ".awards53.lock") end
end

local function register_doc_convert_cmd(buf)
    pcall(vim.api.nvim_buf_del_user_command, buf, "Document53Convert")
    vim.api.nvim_buf_create_user_command(buf, "Document53Convert", function()
        require("awards53.documents.converter").convert_current()
    end, { desc = "Конвертувати поточний документ/картку" })
end

function M.setup(opts)
    local utils = require("awards53.utils")
    local state = require("awards53.state")

    config.setup(opts)
    M.config = config.options
    local augroup = vim.api.nvim_create_augroup("Awards53", { clear = true })

    M.ns_help = vim.api.nvim_create_namespace("awards53_editor_help")
    M.ns_fields = vim.api.nvim_create_namespace("awards53_fields")
    M.ns_rnokpp = vim.api.nvim_create_namespace("awards53_rnokpp")

    local function setup_highlights()
        local hl = vim.api.nvim_get_hl(0, { name = "CursorLine", link = false })
        local bg_color = hl.bg and string.format("#%06x", hl.bg) or "NONE"
        local is_light = vim.o.background == "light" or vim.fn.filereadable(vim.fn.expand("~/.lightmode")) == 1

        local hls = {
            Awards53ActiveField           = { link = "CursorLine", default = true },
            Awards53Help                  = { fg = "#897d6d", bg = "NONE" },
            Awards53HelpText              = { fg = "#897d6d", bg = "NONE", bold = false },
            Awards53RnokppError           = { link = "SpellBad", default = true },
            Awards53HiddenCursor          = { blend = 100, nocombine = true },
            Awards53ChangedIndicator      = { fg = "#b13337", bold = true },
            Awards53Separator             = { link = "Comment", default = true },
            Awards53ChangedIndicatorKarta = { fg = "#b13337", bg = bg_color, bold = true },
            
            Awards53ActiveFieldNC          = { bg = "#222810", fg = "#777777" },
            Awards53ActiveFieldSeparatorNC = { fg = "#3f500a", bg = "#222810" },
            Awards53ActiveFieldSuffixNC    = { fg = "#222810", bg = "NONE" },
            
            Awards53ActiveField           = is_light and { bg = "#d5c4a1", fg = "#3c3836" } or { bg = "#504945", fg = "#ebdbb2" },
            Awards53ActiveFieldPrefix     = is_light and { fg = "#ffffff", bg = "#739313", bold = true } or { fg = "#ebdbb2", bg = "#3f500a" },
            Awards53ActiveFieldSeparator  = is_light and { fg = "#739313", bg = "#d5c4a1" } or { fg = "#3f500a", bg = "#504945" },
            Awards53ActiveFieldSuffix     = is_light and { fg = "#d5c4a1", bg = "NONE" } or { fg = "#504945", bg = "NONE" },
            Awards53ActiveFieldPrefixNC   = is_light and { fg = "#888888", bg = "#3f500a", bold = true } or { fg = "#888888", bg = "#3f500a" },
        }

        for group, val in pairs(hls) do
            vim.api.nvim_set_hl(0, group, val)
        end
    end

    M.setup_highlights = setup_highlights

    -- Реєструємо тільки autocmd, без подвійного виклику під час ініціалізації
    vim.api.nvim_create_autocmd("ColorScheme", { group = augroup, callback = setup_highlights })
    setup_highlights()

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

    vim.api.nvim_create_autocmd("BufReadPost", {
        group = augroup,
        callback = function(args)
            if not vim.api.nvim_buf_is_valid(args.buf) then return end
            local lines = vim.api.nvim_buf_get_lines(args.buf, 0, 15, false)
            if #lines == 0 then return end
            local file_path = vim.api.nvim_buf_get_name(args.buf)

            -- Сценарій А: Заголовок AWARDS53
            if lines[1] and utils.is_section(lines[1]) then
                if state.is_busy() then return end

                local success, lock_path = acquire_lock(file_path)
                if not success then
                    vim.notify("⛔ Файл заблоковано активним процесом Neovim!\nLock-файл: " .. lock_path, vim.log.levels.ERROR)
                    vim.cmd("b #")
                    return
                end

                vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout", "BufDelete", "VimLeavePre" }, {
                    group = vim.api.nvim_create_augroup("Awards53LockCleanup_" .. args.buf, { clear = true }),
                    buffer = args.buf,
                    once = true,
                    callback = function() M.release_lock(file_path) end,
                })

                local all_lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
                local count = 0
                for _, line in ipairs(all_lines) do
                    if utils.is_section(line) then count = count + 1 end
                end

                if count > 1 then
                    vim.notify("Невірна структура даних - декілька входжень AWARDS53!", vim.log.levels.ERROR)
                    if vim.fn.input("Виправити структуру даних? [1-так, 2-ні]: ") == "1" then
                        local found_first = false
                        for i, line in ipairs(all_lines) do
                            if utils.is_section(line) then
                                if found_first then all_lines[i] = "===" else found_first = true end
                            end
                        end
                        vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, all_lines)
                        vim.notify("Структуру виправлено (зайві заголовки замінено на ===)", vim.log.levels.INFO)
                    else
                        M.release_lock(file_path)
                        vim.cmd("b #")
                        return
                    end
                end

                vim.api.nvim_set_current_buf(args.buf)
                vim.cmd("Awards53")
                register_doc_convert_cmd(args.buf)

                local headers = state.headers_list()
                if #headers > 0 and M.config.default_sort == "" then
                    M.config.default_sort = headers[1]
                end
                return
            end

            -- Сценарій Б: Документ DOC53
            for _, line in ipairs(lines) do
                if line:match("^#%+ODT_STYLES_FILE:") or line:match("^#%+DOC53_REQUIRED:") then
                    pcall(function() require("awards53.documents.editor").protect_tech_lines(args.buf) end)
                    pcall(function() require("awards53.abbreviations").register_buffer_abbreviations(args.buf) end)
                    register_doc_convert_cmd(args.buf)
                    break
                end
            end
        end,
    })
end

return M
