local M = {}

local ns_id = vim.api.nvim_create_namespace("doc53_protection")

function M.open(file)
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    vim.opt_local.conceallevel = 2
    
    local buf = vim.api.nvim_get_current_buf()
    
    -- підключаємо розумні абревіатури для цього буфера документів
    pcall(function()
        require("awards53.abbreviations").register_buffer_abbreviations(buf)
    end)
    
    M.protect_tech_lines(buf)
end


function M.protect_tech_lines(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    
    local initial_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local expected_structure = {}
    local seen_meta = {}

    for i, line in ipairs(initial_lines) do
        local full_prefix = line:match("^#%+[A-Z0-9_]+:%s*")
        local meta_prefix = line:match("^#%+ODT_STYLES_FILE:") or line:match("^#%+DOC53_REQUIRED:")

        if meta_prefix then
            local meta_key = meta_prefix:match("^#%+([A-Z0-9_]+):")
            if meta_key and not seen_meta[meta_key] then
                seen_meta[meta_key] = true
                expected_structure[i] = {
                    prefix = meta_prefix,
                    is_meta = true,
                    full_original = line
                }
            end
        elseif full_prefix then
            expected_structure[i] = {
                prefix = full_prefix,
                is_meta = false,
                full_original = line
            }
        end
    end

    local function apply_highlight()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
        
        local actual_buf_line_count = vim.api.nvim_buf_line_count(buf)
        local current_buf_lines = vim.api.nvim_buf_get_lines(buf, 0, actual_buf_line_count, false)

        for row_idx, data in pairs(expected_structure) do
            if row_idx <= actual_buf_line_count then
                local line_idx = row_idx - 1
                local real_line = current_buf_lines[row_idx] or ""
                local real_len = #real_line

                if vim.startswith(real_line, data.prefix) or data.is_meta then
                    if data.is_meta then
                        if real_len > 0 then
                            pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx, 0, {
                                end_col = real_len,
                                conceal = "",
                                hl_group = "NonText"
                            })
                        end
                    else
                        local prefix_len = #data.prefix
                        if real_len >= prefix_len then
                            pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx, 0, {
                                end_col = 2,
                                conceal = "", 
                                hl_group = "NonText"
                            })
                            
                            pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx, prefix_len - 2, {
                                end_col = prefix_len,
                                conceal = " ", 
                                hl_group = "NonText"
                            })
                            
                            vim.api.nvim_buf_add_highlight(buf, ns_id, "Type", line_idx, 2, prefix_len - 2)
                        end
                    end
                end
            end
        end
    end

    apply_highlight()

    -- Захист курсора від заходження на префікс
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        buffer = buf,
        callback = function()
            local cursor = vim.api.nvim_win_get_cursor(0)
            local row = cursor[1]
            local col = cursor[2]
            local data = expected_structure[row]

            if data and not data.is_meta then
                local real_line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
                if vim.startswith(real_line, data.prefix) then
                    local prefix_len = #data.prefix
                    if col < prefix_len then
                        vim.api.nvim_win_set_cursor(0, {row, prefix_len})
                    end
                end
            end
        end,
    })

    -- Інтелектуальний Enter
    vim.keymap.set('i', '<CR>', function()
        local cursor = vim.api.nvim_win_get_cursor(0)
        local row = cursor[1]
        local col = cursor[2]
        local data = expected_structure[row]

        if data and not data.is_meta then
            local real_line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
            if vim.startswith(real_line, data.prefix) then
                local prefix_len = #data.prefix
                if col < prefix_len then
                    vim.api.nvim_win_set_cursor(0, {row, prefix_len})
                    col = prefix_len
                end
                
                if col == prefix_len then
                    local user_text = real_line:sub(prefix_len + 1)
                    vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { data.prefix, user_text })
                    vim.api.nvim_win_set_cursor(0, {row + 1, #data.prefix})
                    apply_highlight()
                    return
                end
            end
        end
        
        return vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
    end, { buffer = buf, expr = false })

    -- Безпечне очищення підказок при вході в режим вставки
    local edited_rows = {}
    vim.api.nvim_create_autocmd("BufEnter", {
        buffer = buf,
callback = function()
            edited_rows = {}
        end,
    })

    vim.api.nvim_create_autocmd("InsertEnter", {
        buffer = buf,
        callback = function()
            local cursor = vim.api.nvim_win_get_cursor(0)
            local row = cursor[1]
            local data = expected_structure[row]

            if data and not data.is_meta and not edited_rows[row] then
                local real_line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
                local prefix = data.prefix
                
                if #real_line > #prefix then
                    vim.api.nvim_buf_set_text(buf, row - 1, #prefix, row - 1, #real_line, { "" })
                    vim.api.nvim_win_set_cursor(0, { row, #prefix })
                end
                
                edited_rows[row] = true
            end
        end,
    })
    
    -- логіка відновлення мета-рядків
    vim.api.nvim_buf_attach(buf, false, {
        on_bytes = function(_, _, _, start_row, _, _, _, _, _, _, _, _)
            vim.schedule(function()
                if not vim.api.nvim_buf_is_valid(buf) then return end
                
                local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

                for row_idx, data in pairs(expected_structure) do
                    if data.is_meta then
                        local current_line = all_lines[row_idx] or ""
                        -- якщо рядок стерли або змінили
                        if current_line ~= data.full_original then
                            -- перевіряємо чи він є десь у файлі
                            local found = false
                            for _, l in ipairs(all_lines) do
                                if l == data.full_original then
                                    found = true
                                    break
                                end
                            end
                            -- якщо немає — вставляємо саме на його позицію
                            if not found then
                                vim.api.nvim_buf_set_lines(buf, row_idx-1, row_idx-1, false, { data.full_original })
                            end
                        end
                    else
                        -- контроль звичайних префіксів
                        local current_line = all_lines[row_idx] or ""
                        if not vim.startswith(current_line, data.prefix) then
                            local user_text = current_line
                            vim.api.nvim_buf_set_lines(buf, row_idx-1, row_idx, false, { data.prefix .. user_text })
                        end
                    end
                end

                apply_highlight()
            end)
        end
    })


end

return M
