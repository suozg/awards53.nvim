local M = {}

local PROTECTED_META = {
    ODT_STYLES_FILE = true,
    DOC53_REQUIRED = true,
}

local ns_placeholders = vim.api.nvim_create_namespace("doc53_placeholders")

local function is_doc53_line(line)
    return line:match("^#%+[A-Z0-9_]+:%s?.*$") ~= nil
end

local function parse_doc53_line(line)
    local key, value = line:match("^#%+([A-Z0-9_]+):%s?(.*)$")
    if not key then
        return nil, nil
    end
    return "#+" .. key .. ": ", value or ""
end

local function is_fully_protected_line(line)
    local key = line:match("^#%+([A-Z0-9_]+):")
    if not key then
        return false
    end
    return PROTECTED_META[key] == true
end

local function restore_row(buf, row, prefix, value)
    local restored = prefix .. value
    vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { restored })
    vim.api.nvim_win_set_cursor(0, { row, #prefix })
end

-- Віртуальний текст (підказки), який не записується у файл
local function update_placeholders(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    vim.api.nvim_buf_clear_namespace(buf, ns_placeholders, 0, -1)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    for row_idx, line in ipairs(lines) do
        local key, value = line:match("^#%+([A-Z0-9_]+):%s?(.*)$")
        
        if key == "HEAD" and (value == nil or value == "") then
            vim.api.nvim_buf_set_extmark(buf, ns_placeholders, row_idx - 1, #line, {
                -- 1. Підказка безпосередньо в рядку :
                virt_text = { { " [ АДРЕСАТ ]", "Comment" } },
                virt_text_pos = "eol", -- додається в кінець рядка #+BODY:
            })
        end

        if key == "BODY" and (value == nil or value == "") then
            vim.api.nvim_buf_set_extmark(buf, ns_placeholders, row_idx - 1, #line, {
                -- 1. Підказка безпосередньо в рядку #+BODY:
                virt_text = { { " [ ТЕКСТ ДОКУМЕНТА ]", "Comment" } },
                virt_text_pos = "eol", -- додається в кінець рядка #+BODY:
                virt_lines = {
                    { { " Якщо треба нове поле: у шаблон .org додайте, наприклад, #+NUMBER:", "Comment" } },
                    { { " а у шаблон .odt додайте __NUMBER__ на початку потрібного абзацу.", "Comment" } },
                },
                virt_lines_above = false, -- показувати нижче рядка #+BODY:
            })
        end
        
    end
end

local function hide_protected_lines(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    for row_idx, line in ipairs(lines) do
        if is_fully_protected_line(line) then
            local ns = vim.api.nvim_create_namespace("doc53_hidden_" .. tostring(buf) .. "_" .. row_idx)

            pcall(vim.api.nvim_buf_set_extmark, buf, ns, row_idx - 1, 0, {
                end_col = #line,
                conceal = " ",
                hl_group = "Conceal",
            })
        end
    end
end

local function protect_line(buf, row)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""

    -- Повністю захищені метадані
    if is_fully_protected_line(line) then
        local key = line:match("^#%+([A-Z0-9_]+):")
        if key then
            local prefix = "#+" .. key .. ": "
            local value = line:sub(#prefix + 1)
            local restored = prefix .. value

            if line ~= restored then
                vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { restored })
            end

            local line_count = vim.api.nvim_buf_line_count(buf)
            if row >= line_count then
                vim.api.nvim_win_set_cursor(0, { math.max(1, line_count), 0 })
            else
                vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
            end
        end
        return
    end

    -- Для частково захищених #+FIELD:
    if not is_doc53_line(line) then
        return
    end

    local prefix, value = parse_doc53_line(line)
    if not prefix then
        return
    end

    local prefix_len = #prefix
    local cursor = vim.api.nvim_win_get_cursor(0)
    local col = cursor[2]

    if line:sub(1, prefix_len) ~= prefix then
        restore_row(buf, row, prefix, value)
        return
    end

    -- Не дозволяємо курсору ставати всередину або перед префіксом
    if col < prefix_len then
        vim.api.nvim_win_set_cursor(0, { row, prefix_len })
    end
end

local function protect_doc53_buffer(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    vim.wo[0].conceallevel = 2
    vim.wo[0].concealcursor = "niv"

    hide_protected_lines(buf)
    update_placeholders(buf)

    local group_name = "Awards53DocsProtection_" .. tostring(buf)
    local group = vim.api.nvim_create_augroup(group_name, { clear = true })

    vim.api.nvim_create_autocmd({
        "CursorMoved",
        "CursorMovedI",
        "TextChangedI",
        "TextChanged",
        "InsertEnter",
        "InsertLeave",
        "BufWinEnter",
        "WinEnter",
    }, {
        group = group,
        buffer = buf,
        callback = function()
            local row = vim.api.nvim_win_get_cursor(0)[1]
            hide_protected_lines(buf)
            protect_line(buf, row)
            update_placeholders(buf)
        end,
    })

    local function on_protected_metadata_row()
        local row = vim.api.nvim_win_get_cursor(0)[1]
        local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""

        if not is_fully_protected_line(line) then
            return false
        end

        vim.api.nvim_echo({
            { "Documents53: це службове поле заблоковано", "WarningMsg" },
        }, false, {})

        return true
    end

    -- Перехоплення клавіш входу в режим редагування (щоб курсор не стрибав на '0' при клавіші 'I')
    for _, key in ipairs({ "i", "I", "a", "A" }) do
        vim.keymap.set("n", key, function()
            if on_protected_metadata_row() then
                return
            end

            local row = vim.api.nvim_win_get_cursor(0)[1]
            local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""

            if is_doc53_line(line) then
                local prefix = parse_doc53_line(line)
                if prefix then
                    local prefix_len = #prefix
                    local cursor = vim.api.nvim_win_get_cursor(0)

                    if key == "I" or cursor[2] < prefix_len then
                        vim.api.nvim_win_set_cursor(0, { row, prefix_len })
                        vim.cmd("startinsert")
                        return
                    end
                end
            end

            vim.api.nvim_feedkeys(
                vim.api.nvim_replace_termcodes(key, true, false, true),
                "n",
                false
            )
        end, { buffer = buf, silent = true, noremap = true })
    end

    -- Блокування інших небезпечних дій
    for _, key in ipairs({
        "o", "O", "R", "r", "x", "X", "D", "C", "s", "S", "J", "dd", "cc", "yy", "p", "P"
    }) do
        vim.keymap.set("n", key, function()
            if on_protected_metadata_row() then
                return
            end

            vim.api.nvim_feedkeys(
                vim.api.nvim_replace_termcodes(key, true, false, true),
                "n",
                false
            )
        end, { buffer = buf, silent = true, noremap = true })
    end
end

-- Встановлення курсора на #+BODY: та активація режиму редагування
local function focus_body_and_insert(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for row_idx, line in ipairs(lines) do
        local key = line:match("^#%+([A-Z0-9_]+):")
        if key == "BODY" then
            local prefix = "#+BODY: "
            vim.api.nvim_win_set_cursor(0, { row_idx, #prefix })
            vim.cmd("startinsert!")
            return
        end
    end
end

function M.open(file)
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    local buf = vim.api.nvim_get_current_buf()

    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = "niv"

    vim.bo[buf].modifiable = true
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "org"

    protect_doc53_buffer(buf)

    -- Автоматично переходимо на #+BODY: та вмикаємо Insert mode
    vim.schedule(function()
        focus_body_and_insert(buf)
    end)

    vim.notify(
        "Documents53: службові рядки приховані і заблоковані.",
        vim.log.levels.INFO
    )
end

function M.protect_tech_lines(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    protect_doc53_buffer(buf)
end

return M
