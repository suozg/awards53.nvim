-- =============================================================================
-- AUTOCMDS
-- =============================================================================
local group = vim.api.nvim_create_augroup("UserConfig", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
    group = group,
pattern = { "org", "text" },
    callback = function()
        vim.opt_local.wrap = true

        vim.opt_local.spell = true
        vim.opt_local.spelllang = { "uk", "en_us" }

        -- Увімкнути класичний синтаксис і змусити його перевіряти весь текст
        vim.cmd("syntax on")
        vim.cmd("syntax spell toplevel")
    end,
})

vim.api.nvim_create_autocmd("TextYankPost", {
    group = group,
    callback = function()
        -- Безпечний виклик нової або старої функції підсвічування янку
        pcall(vim.hl.on_yank, { timeout = 200 })
    end,
})

vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.org",
    callback = function()
        vim.fn.jobstart({ "pkill", "-RTMIN+10", "dwmblocks" })
    end,
})

local clean_group = vim.api.nvim_create_augroup("CleanUndoHistory", { clear = true })

-- 1. Видалення undo-файла при видаленні/переміщенні самого файла
vim.api.nvim_create_autocmd({ "BufWritePost", "BufDelete", "BufUnload" }, {
  group = clean_group,
  callback = function(args)
    local file = vim.api.nvim_buf_get_name(args.buf)
    if file ~= "" and not vim.startswith(file, "term://") and vim.fn.filereadable(file) == 0 then
      local undofile = vim.fn.undofile(file)
      if undofile ~= "" and vim.fn.filereadable(undofile) == 1 then
        os.remove(undofile)
      end
    end
  end,
})

-- 2. Асинхронне очищення undo-файлів, які не змінювалися понад 30 днів
vim.api.nvim_create_autocmd("VimEnter", {
  group = clean_group,
  callback = function()
    local undo_dir = vim.fn.expand("~/.local/state/nvim/undo")
    if vim.fn.isdirectory(undo_dir) == 1 then
      vim.fn.jobstart({
        "find", undo_dir, "-type", "f", "-mtime", "+30", "-delete"
      })
    end
  end,
})

-- -----------------------------------------------------------------------------
-- Управління розкладкою клавіатури (xkb-switch + dwmblocks)
-- -----------------------------------------------------------------------------
local saved_layout = "us"

local function save_current_layout()
    local handle = io.popen("xkb-switch -p")
    if handle then
        local current = handle:read("*l")
        handle:close()
        if current and current ~= "" then
            saved_layout = current
        end
    end
end

-- Універсальна функція для зміни розкладки, оновлення файлу та статусу в dwm
local function set_layout(layout)
    vim.fn.jobstart({ "xkb-switch", "-s", layout })
    
    local display_text
    if layout == "ua" then
        display_text = "🌻UA"
    else
        display_text = "🗽US"
    end

    local f = io.open("/tmp/dwm_layout", "w")
    if f then
        f:write(display_text)
        f:close()
    end

    vim.fn.jobstart({ "pkill", "-RTMIN+1", "dwmblocks" })
end

-- Повертаємо розкладку, яка була до виходу з Insert
vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function()
        if saved_layout ~= "" then
            set_layout(saved_layout)
        end
    end,
})

-- При виході з Insert зберігаємо мову та перемикаємо на 'us' 
-- (але тільки якщо ми не вводимо абревіатуру через діалог vim.ui.input)
vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function()
        -- Якщо активний командний рядок (йде введення через діалог), не чіпаємо розкладку
        if vim.fn.mode() == "c" then return end
        
        save_current_layout()
        set_layout("us")
    end,
})

----------- кінець управління розкладкою -------------------------

-- прибирає вертикальну лінію-індикатор довжини рядка для вікон orgagenda
vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "orgagenda" }, 
    callback = function()
        vim.opt_local.colorcolumn = ""
    end,
})
