local M = {}

local defaults = {
    separator = "::",
    section = "AWARDS53",
    default_sort = "1",
    record_separator = "===",
}

M.config = {}

function M.setup(opts)
    local utils = require("awards53.utils")
    local state = require("awards53.state")

    M.config = vim.tbl_deep_extend(
        "force",
        defaults,
        opts or {}
    )

    -- Група автокоманд плагіна.
    -- clear = true робить setup() безпечним при повторному виклику.
    local augroup = vim.api.nvim_create_augroup("Awards53", {
        clear = true,
    })

    -- 1. Реєстрація namespace для підсвічування
    M.ns_help = vim.api.nvim_create_namespace("awards53_editor_help")
    M.ns_fields = vim.api.nvim_create_namespace("awards53_fields")
    M.ns_rnokpp = vim.api.nvim_create_namespace("awards53_rnokpp")

    -- 2. Централізоване визначення кольорів
    vim.api.nvim_set_hl(0, "Awards53Help", {
        fg = "#897d6d",
        bg = "NONE",
    })

    vim.api.nvim_set_hl(0, "Awards53HelpText", {
        fg = "#897d6d",
        bg = "NONE",
        bold = false,
    })

    vim.api.nvim_set_hl(0, "Awards53RnokppError", {
        fg = "#FFFFFF",
        bg = "#FF0000",
        bold = true,
    })

    vim.api.nvim_set_hl(0, "Awards53ActiveFieldPrefix", {
        fg = "#ffffff",
        bg = "#739313",
        bold = true,
    })

    vim.api.nvim_set_hl(0, "Awards53HiddenCursor", {
        blend = 100,
        nocombine = true,
    })

    vim.api.nvim_set_hl(0, "Awards53Separator", {
        link = "Comment",
    })

    vim.api.nvim_set_hl(0, "Awards53ActiveFieldSeparator", {
        fg = "#739313",
    })

    local function update_suffix_color()
        local hl = vim.api.nvim_get_hl(0, {
            name = "CursorLine",
            link = false,
        })

        local bg_color = hl.bg
            and string.format("#%06x", hl.bg)
            or "NONE"

        vim.api.nvim_set_hl(0, "Awards53ActiveFieldSuffix", {
            fg = bg_color,
            bg = "NONE",
        })

        vim.api.nvim_set_hl(0, "Awards53ChangedIndicatorKarta", {
            fg = "#b13337",
            bg = bg_color,
            bold = true,
        })
    end

    update_suffix_color()

    vim.api.nvim_set_hl(0, "Awards53ChangedIndicator", {
        fg = "#b13337",
        bold = true,
    })

    vim.api.nvim_create_autocmd("ColorScheme", {
        group = augroup,
        pattern = "*",
        callback = update_suffix_color,
    })

    -- 3. Реєстрація базових команд плагіна
    require("awards53.commands").setup()

    -- 4. Реєстрація Documents53.
    -- Видаляємо стару версію, якщо setup() викликається повторно.
    pcall(vim.api.nvim_del_user_command, "Documents53")

    vim.api.nvim_create_user_command("Documents53", function()
        local status, doc_init = pcall(require, "awards53.documents.init")

        if status and doc_init and doc_init.open then
            doc_init.open()
        else
            require("awards53.documents.converter").convert_current()
        end
    end, {
        desc = "Головне меню / робота з Documents53",
    })

    -- 5. Автовизначення типу файлу при відкритті
    vim.api.nvim_create_autocmd("BufReadPost", {
        group = augroup,
        callback = function(args)
            vim.schedule(function()
                if not vim.api.nvim_buf_is_valid(args.buf) then
                    return
                end

                local lines = vim.api.nvim_buf_get_lines(
                    args.buf,
                    0,
                    15,
                    false
                )

                if #lines == 0 then
                    return
                end

                if lines[1] and utils.is_section(lines[1]) then
                    local all_lines = vim.api.nvim_buf_get_lines(
                        args.buf,
                        0,
                        -1,
                        false
                    )

                    local count = 0

                    for _, line in ipairs(all_lines) do
                        if utils.is_section(line) then
                            count = count + 1
                        end
                    end

                    if count > 1 then
                        vim.notify(
                            "Невірна структура даних - декілька входжень AWARDS53!",
                            vim.log.levels.ERROR
                        )

                        local choice = vim.fn.input(
                            "Виправити структуру даних? [1-так, 2-ні]: "
                        )

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

                            vim.api.nvim_buf_set_lines(
                                args.buf,
                                0,
                                -1,
                                false,
                                all_lines
                            )

                            vim.cmd("redraw")

                            vim.notify(
                                "Структуру виправлено (зайві заголовки замінено на ===)",
                                vim.log.levels.INFO
                            )

                        elseif choice == "2" then
                            vim.cmd("b #")
                            return
                        end
                    end

                    vim.api.nvim_set_current_buf(args.buf)
                    vim.cmd("Awards53")

                    -- Буферна команда. Перед створенням видаляємо
                    -- попередню версію, якщо вона вже існує.
                    pcall(
                        vim.api.nvim_buf_del_user_command,
                        args.buf,
                        "Document53Convert"
                    )

                    vim.api.nvim_buf_create_user_command(
                        args.buf,
                        "Document53Convert",
                        function()
                            require("awards53.documents.converter")
                                .convert_current()
                        end,
                        {
                            desc = "Універсальна конвертація даних Awards53",
                        }
                    )

                    local headers = state.headers_list()

                    if #headers > 0 and M.config.default_sort == "" then
                        M.config.default_sort = headers[1]
                    end

                    return
                end

                local is_doc53 = false

                for _, line in ipairs(lines) do
                    if line:match("^#%+ODT_STYLES_FILE:")
                        or line:match("^#%+DOC53_REQUIRED:")
                    then
                        is_doc53 = true
                        break
                    end
                end

                if is_doc53 then
                    pcall(function()
                        require("awards53.documents.editor")
                            .protect_tech_lines(args.buf)
                    end)

                    pcall(function()
                        require("awards53.abbreviations")
                            .register_buffer_abbreviations(args.buf)
                    end)

                    -- Буферна команда також може вже існувати.
                    pcall(
                        vim.api.nvim_buf_del_user_command,
                        args.buf,
                        "Document53Convert"
                    )

                    vim.api.nvim_buf_create_user_command(
                        args.buf,
                        "Document53Convert",
                        function()
                            require("awards53.documents.converter")
                                .convert_current()
                        end,
                        {
                            desc = "Конвертувати поточний Org-mode документ у ODT",
                        }
                    )
                end
            end)
        end,
    })
end

return M
