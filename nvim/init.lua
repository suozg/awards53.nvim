--- leader key
vim.g.mapleader = " "
--- скриваем поле командной строки
vim.opt.cmdheight = 0

-- завантажуємо системні опції та автокоманди,
require("config.options")
require("config.autocmds") 

-- Запускаємо менеджер плагінів, який підтягне теми та розширення
require("config.lazy")

-- Налаштовуємо зовнішній вигляд та гарячі клавіші
require("config.theme")
require("config.statusline")
require("config.keymaps")

-- Ініціалізуємо плагін карток
require("awards53").setup()

