local M = {}

local ns_id = vim.api.nvim_create_namespace("doc53_protection")

function M.open(file)
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    vim.opt_local.conceallevel = 2
    M.protect_tech_lines()
end

function M.protect_tech_lines()
    local buf = vim.api.nvim_get_current_buf()
    
    local initial_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local expected_structure = {}
    local max_protected_row = 0

    for i, line in ipairs(initial_lines) do
        local full_prefix, clean_name = line:match("^(#%+([A-Z0-9_]+):%s*)")
        local meta_prefix = line:match("^(#%+ODT_STYLES_FILE:)") or line:match("^(#%+DOC53_REQUIRED:)")

        if meta_prefix then
            expected_structure[i] = {
                prefix = meta_prefix,
                is_meta = true,
                full_original = line
            }
            max_protected_row = i
        elseif full_prefix and clean_name then
            expected_structure[i] = {
                prefix = full_prefix,
                clean_name = clean_name,
                is_meta = false
            }
            max_protected_row = i
        end
    end

    -- Безпечна функція приховування
    local function apply_highlight()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
        
        -- Отримуємо поточний реальний вміст буфера, щоб уникнути out of range
        local current_buf_lines = vim.api.nvim_buf_get_lines(buf, 0, max_protected_row, false)

        for row_idx, data in pairs(expected_structure) do
            local line_idx = row_idx - 1
            local real_line = current_buf_lines[row_idx] or ""
            local real_len = #real_line

            if data.is_meta then
                -- Безпечно приховуємо технічну шапку, тільки якщо рядок існує
                if real_len > 0 then
                    pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx, 0, {
                        end_col = real_len,
                        conceal = "",
                        hl_group = "NonText"
                    })
                end
            else
                -- Для звичайних полів (наприклад, #+BODY: )
                local prefix_len = #data.prefix
                -- Перевіряємо, чи поточний рядок у буфері дійсно має потрібну довжину
                if real_len >= prefix_len then
                    -- 1. Ховаємо "#+"
                    pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx, 0, {
                        end_col = 2,
                        conceal = "", 
                        hl_group = "NonText"
                    })
                    
                    -- 2. Ховаємо двокрапку та пробіл
                    pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx, prefix_len - 2, {
                        end_col = prefix_len,
                        conceal = " ", 
                        hl_group = "NonText"
                    })
                    
                    -- 3. Підсвічуємо назву поля
                    vim.api.nvim_buf_add_highlight(buf, ns_id, "Type", line_idx, 2, prefix_len - 2)
                end
            end
        end
    end

    apply_highlight()

    -- 2. Низькорівневий контроль
    vim.api.nvim_buf_attach(buf, false, {
        on_bytes = function(_, _, _, start_row, _, _, _, _, _, _, _, _)
            if expected_structure[start_row + 1] then
                vim.schedule(function()
                    if not vim.api.nvim_buf_is_valid(buf) then return end
                    
                    local current_lines = vim.api.nvim_buf_get_lines(buf, 0, max_protected_row, false)
                    local changed = false

                    for row_idx, data in pairs(expected_structure) do
                        local current_line = current_lines[row_idx]
                        
                        if not current_line then
                            changed = true
                            break
                        end

                        if data.is_meta then
                            if current_line ~= data.full_original then changed = true end
                        else
                            if current_line:sub(1, #data.prefix) ~= data.prefix then
                                changed = true
                            end
                        end
                    end

                    if changed then
                        vim.api.nvim_command("noautocmd silent!")
                        
                        local restored_lines = vim.api.nvim_buf_get_lines(buf, 0, max_protected_row, false)
                        for row_idx, data in pairs(expected_structure) do
                            if restored_lines[row_idx] then
                                if data.is_meta then
                                    restored_lines[row_idx] = data.full_original
                                else
                                    local user_text = restored_lines[row_idx]:sub(#data.prefix + 1)
                                    if not restored_lines[row_idx]:match("^#%+") then
                                        user_text = restored_lines[row_idx]
                                    end
                                    restored_lines[row_idx] = data.prefix .. user_text
                                end
                            end
                        end

                        vim.api.nvim_buf_set_lines(buf, 0, max_protected_row, false, restored_lines)
                        apply_highlight()
                        vim.api.nvim_command("autocmd!")
                    end
                end)
            end
        end
    })
end

return M
