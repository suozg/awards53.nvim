-- ====================="cmp.utils.feedkeys".run(144)
-- ========================================================
-- 0. СИСТЕМНІ НАЛАШТУВАННЯ ТА ШЛЯХИ
-- =============================================================================
vim.g.python3_host_prog = '~/venv/bin/python3'
vim.env.PATH = "~/venv/bin:" .. vim.env.PATH
vim.opt.runtimepath:append(vim.fn.expand("~/.local/share/nvim/site"))

-- Вимикаємо непотрібні провайдери для прискорення завантаження
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0

-- Робимо так, щоб Neovim розумів українську розкладку в Normal/Visual режимах
vim.opt.langmap = [[ЙQ,ЦW,УE,КR,ЕT,НY,ГU,ШI,ЩO,ЗP,Х{,Ї},ФA,ІS,ВD,АF,ПG,РH,ОJ,ЛK,ДL,Ж\:,Є\",ЯZ,ЧX,СC,МV,ИB,ТN,ЬM,Б\<,Ю\>,йq,цw,уe,кr,еt,нy,гu,шi,щo,зp,х[,ї],фa,іs,вd,аf,пg,рh,оj,лk,дl,ж\;,є\',яz,чx,сc,мv,иb,тn,ьm,б\,,ю.]]


-- =============================================================================
-- 2. OPTIONS (Налаштування)
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
vim.g.netrw_banner = 0
opt.whichwrap:append("<,>,[,],h,l")
