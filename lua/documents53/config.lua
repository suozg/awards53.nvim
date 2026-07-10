local M = {}

M.template_dir = vim.fn.stdpath("config") .. "/templates/templates53"
M.selection_file = (vim.env.XDG_RUNTIME_DIR or "/tmp") .. "/doc53-selection"

return M
