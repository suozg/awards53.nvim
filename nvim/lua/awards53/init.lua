local M = {}

local defaults = {
    separator = "::",
    section = "AWARDS53",
    default_sort = "1", -- Автоматично сортувати/шукати за першим полем
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

    require("awards53.commands").setup()
    
    vim.api.nvim_create_user_command("Documents53", function()
        require("awards53.documents").open() -- шлях до модуля документів
    end, {})

    vim.api.nvim_create_autocmd("BufReadPost", {
        callback = function(args)
            vim.schedule(function()
                if not vim.api.nvim_buf_is_valid(args.buf) then
                    return
                end

                -- Зчитуємо перші кілька рядків для перевірки наявності маркера
                local lines = vim.api.nvim_buf_get_lines(args.buf, 0, 5, false)
 
                if lines[1] and utils.is_section(lines[1]) then
                    vim.api.nvim_set_current_buf(args.buf)
                    vim.cmd("Awards53")
                    
                    -- Після успішного відкриття карток беремо перше ліпше поле 
                    -- файлу як дефолтне для швидкого пошуку (клавіша /) та сортування (клавіша S)
                    local headers = state.headers_list()
                    if #headers > 0 and M.config.default_sort == "" then
                        M.config.default_sort = headers[1]
                    end
                end
            end)
        end,
    })

end

return M
