local M = {}

local state = require("awards53.state")

function M.render()
    local file_name = ""
    local buf = state.get_source_buffer()
    if buf and vim.api.nvim_buf_is_valid(buf) then
        local full_path = vim.api.nvim_buf_get_name(buf)
        if full_path ~= "" then
            file_name = vim.fn.fnamemodify(full_path, ":t") .. " │ "
        end
    end

    local is_modified = false
    if state.is_changed then is_modified = true end
    if buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then is_modified = true end

    local editor_ok, editor = pcall(require, "awards53.editor")
    if editor_ok and editor.buf and vim.api.nvim_buf_is_valid(editor.buf) and vim.bo[editor.buf].modified then
        is_modified = true
    end

    local mod_flag = is_modified and " [+] " or " "
    local bookmark_flag = state.has_bookmark() and " 🔖[Закладка]" or ""

    return string.format(
        "%%#StatusLine#Файл: %sКартка: %d/%d%s%s │ Переміщення: h◄ l► [[◀◀ ]]▶▶ N │ Операції: S O⇄ A 0 dp✥ dd✗ y⎘ p󰆑 :w🖪 :q⏻ | Довідка: ? ",
        file_name,
        state.index(),
        state.count(),
        mod_flag,
        bookmark_flag
    )
end

return M
