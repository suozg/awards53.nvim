-- =============================================================================
-- СИСТЕМНІ НАЛАШТУВАННЯ ТА ШЛЯХИ
-- =============================================================================
vim.g.python3_host_prog = vim.fn.expand('~/venv/bin/python3')
vim.env.PATH = vim.fn.expand("~/venv/bin:") .. vim.env.PATH
vim.opt.runtimepath:append(vim.fn.expand("~/.local/share/nvim/site"))

vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0
vim.g.netrw_banner = 0

-- Neovim підтримка української розкладки в Normal/Visual
vim.opt.langmap = [[ЙQ,ЦW,УE,КR,ЕT,НY,ГU,ШI,ЩO,ЗP,Х{,Ї},ФA,ІS,ВD,АF,ПG,РH,ОJ,ЛK,ДL,Ж\:,Є\",ЯZ,ЧX,СC,МV,ИB,ТN,ЬM,Б\<,Ю\>,йq,цw,уe,кr,еt,нy,гu,шi,щo,зp,х[,ї],фa,іs,вd,аf,пg,рh,оj,лk,дl,ж\;,є\',яz,чx,сc,мv,иb,тn,ьm,б\,,ю.]]

-- Автоматичне перетворення українських літер у командному рядку для збереження та виходу
vim.cmd([[
    cnoreabbrev ц w
    cnoreabbrev Ц W
    cnoreabbrev й q
    cnoreabbrev Й Q
    cnoreabbrev у e
    cnoreabbrev У E
]])

-- =============================================================================
-- OPTIONS
-- =============================================================================
local opt = vim.opt
opt.number = true
opt.tabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.incsearch = true
opt.ignorecase = true
opt.smartcase = true
opt.termguicolors = true
opt.clipboard = "unnamedplus"
opt.cursorline = true
opt.scrolloff = 10
opt.sidescrolloff = 8
opt.signcolumn = "yes"
opt.colorcolumn = "100"
opt.mouse = "a"
opt.completeopt = "menuone,noselect"
opt.list = false
opt.listchars = { tab = '→ ', trail = '·', eol = '↲', space = '·' }
opt.foldmethod = "indent"
opt.foldlevelstart = 99
opt.foldenable = true
opt.updatetime = 300
opt.conceallevel = 2
opt.concealcursor = 'nc'
opt.whichwrap:append("<,>,[,],h,l")
opt.laststatus = 3  -- лише один рядок стану для всього екрану
-- бекап
opt.undofile = true
opt.undodir = vim.fn.expand("~/.local/state/nvim/undo")
opt.timeoutlen = 500
opt.ttimeoutlen = 0
opt.backup = false
opt.writebackup = false
opt.swapfile = false
-- Автоматичне очищення файлів undo, старіших за 90 днів
vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("CleanUndoHistory", { clear = true }),
  callback = function()
    local undo_dir = vim.fn.expand("~/.local/state/nvim/undo")
    if vim.fn.isdirectory(undo_dir) == 1 then
      -- Команда виконується асинхронно, щоб не уповільнювати запуск Neovim
      vim.fn.jobstart({
        "find", undo_dir, "-type", "f", "-atime", "+90", "-delete"
      })
    end
  end,
})
