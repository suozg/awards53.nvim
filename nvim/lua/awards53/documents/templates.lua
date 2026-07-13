local M = {}

local config = require("awards53.documents.config")

function M.list(mode)
    local result = {}

    local root = config.template_dir
    if mode then
        root = root .. "/" .. mode
    end

    local dirs = vim.fn.glob(root .. "/*", false, true)

    for _, dir in ipairs(dirs) do
        if vim.fn.isdirectory(dir) == 1 then
            local org = vim.fn.glob(dir .. "/*.org", false, true)[1]
            local ott = vim.fn.glob(dir .. "/*.ott", false, true)[1]

            if org and ott then
                table.insert(result, {
                    id = vim.fn.fnamemodify(dir, ":t"),
                    path = dir,
                    org = org,
                    ott = ott,
                })
            else
                vim.notify(
                    "Некоректний шаблон: " .. dir,
                    vim.log.levels.ERROR
                )
            end
        end
    end

    return result
end

function M.find(path, mode)
    for _, tpl in ipairs(M.list(mode)) do
        if tpl.path == path then
            return tpl
        end
    end
end

return M
