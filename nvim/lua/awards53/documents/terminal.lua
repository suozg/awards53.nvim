local M = {}

local config = require("awards53.documents.config")

function M.pick(mode, callback)
    local width = math.floor(vim.o.columns * 0.6)
    local height = math.floor(vim.o.lines * 0.6)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local buf = vim.api.nvim_create_buf(false, true)

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
    })

    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false

    local dir = config.template_dir

    if mode == "documents" then
        dir = config.template_dir .. "/documents"
    elseif mode == "awards" then
        dir = config.template_dir .. "/awards"
    end

    vim.fn.termopen({
        "doc53-picker",
        dir,
    }, {
        on_exit = function(_, code)
            vim.schedule(function()

                if vim.api.nvim_win_is_valid(win) then
                    vim.api.nvim_win_close(win, true)
                end

                if vim.api.nvim_buf_is_valid(buf) then
                    vim.api.nvim_buf_delete(buf, { force = true })
                end

                if code ~= 0 then
                    return
                end

                if vim.fn.filereadable(config.selection_file) == 0 then
                    return
                end

                local path = vim.fn.readfile(config.selection_file)[1]

                if callback then
                    callback(path)
                end

            end)
        end,
    })

    vim.cmd("startinsert")
end

return M
