local M = {}

local config = require("awards53.documents.config")

function M.list()
    local result = {}
    local dirs = vim.fn.glob(config.template_dir .. "/*", false, true)

    for _, dir in ipairs(dirs) do
        if vim.fn.isdirectory(dir) == 1 then
            local org = vim.fn.glob(dir .. "/*.org", false, true)[1]
            -- Шукаємо .ott файл у тій самій директорії
            local ott = vim.fn.glob(dir .. "/*.ott", false, true)[1]

            if not org then
                vim.notify(
                    "Помилка: Відсутній шаблон .org: " .. vim.fn.fnamemodify(dir, ":t"),
                    vim.log.levels.ERROR
                )
            elseif not ott then
                vim.notify(
                    "Помилка: Відсутній шаблон .ott: " .. vim.fn.fnamemodify(dir, ":t"), 
                    vim.log.levels.ERROR
                )
            else
                table.insert(result, {
                    id = vim.fn.fnamemodify(dir, ":t"),
                    path = dir,
                    org = org,
                    ott = ott,
                })
            end
        end
    end

    return result
end

function M.find(path)
    for _, tpl in ipairs(M.list()) do
        if tpl.path == path then
            return tpl
        end
    end
end

return M
