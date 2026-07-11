-- ~/.config/nvim
-- │
-- ├── init.lua
-- │
-- └── lua
--     ├── config
--     │   ├── autocmds.lua
--     │   ├── keymaps.lua
--     │   ├── lazy.lua
--     │   ├── options.lua
--     │   ├── statusline.lua
--     │   └── theme.lua
--     │
--     └── plugins
--         ├── editor.lua
--         ├── lsp.lua
--         ├── orgmode.lua
--         ├── treesitter.lua
--         └── ui.lua

--------------  СИСТЕМА ДОКУМЕНТІВ AWARDS53 ----------------
-- lua/
-- └── awards53/
--     ├── init.lua            -- Головний файл ініціалізації системи
--     ├── state.lua           -- Стан карток 
--     ├── parser.lua          -- Парсер Org-структури
--     ├── serializer.lua      -- Збереження карток назад у файл
--     ├── utils.lua           -- Перевірка РНОКПП та хелпери
--     ├── actions.lua         -- Форматування, сортування
--     ├── ui.lua              -- Головне вікно інтерфейсу карток
--     ├── body.lua            -- Рендеринг полів
--     ├── header.lua          -- Рендеринг заголовків карток
--     ├── status.lua          -- Статус-рядок вікна карток
--     ├── editor.lua          -- Редактор поля картки (Tabedit)
--     ├── abbreviations.lua   -- Автозаміни текста (3АКого, 53ди)
--     │
--     └── documents/          -- 📁 генератор документів
--         ├── init.lua        -- Логіка запуску генератора 
--         ├── templates.lua   -- Шаблони рапортів/довідок
--         ├── builder.lua     -- Збирання підсумкових документів
--         └── ...             -- інші файли, генератора документів


-- ---


--- leader key
vim.g.mapleader = " "

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

