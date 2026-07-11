-- =============================================================================
-- AUTOCMDS
-- =============================================================================
local group = vim.api.nvim_create_augroup("UserConfig", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "org", "text" },
    callback = function()
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
        vim.highlight.on_yank({ timeout = 200 })
    end,
})

vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.org",
    callback = function()
        vim.fn.jobstart({ "pkill", "-RTMIN+10", "dwmblocks" })
    end,
})

vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function()
        vim.api.nvim_set_hl(0, "StatusLine", { link = "StatusLineInsert" })
    end,
})

vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function()
        vim.api.nvim_set_hl(0, "StatusLine", { link = "StatusLineNormal" })
    end,
})

local saved_layout = "us"

vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function()
        if saved_layout ~= "" then
            vim.fn.jobstart({ "xkb-switch", "-s", saved_layout })
            vim.fn.jobstart({ "pkill", "-RTMIN+1", "dwmblocks" })
        end
    end,
})

vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function()
        local handle = io.popen("xkb-switch -p")
        if handle then
            local current = handle:read("*l")
            handle:close()
            if current and current ~= "" then
                saved_layout = current
            end
        end

        if saved_layout ~= "us" then
            vim.fn.jobstart({ "xkb-switch", "-s", "us" })
            vim.fn.jobstart({ "pkill", "-RTMIN+1", "dwmblocks" })
        end
    end,
})

-- кольори орфографії для будь-яких тем та терміналів
vim.api.nvim_create_autocmd({ "ColorScheme", "VimEnter" }, {
    pattern = "*",
    callback = function()
        -- Замість підкреслення робимо помилковим словам темно-червоний або яскравий фон
        -- ctermbg відповідає за звичайний термінал, bg — за GUI/TrueColor
        vim.api.nvim_set_hl(0, "SpellBad", { 
            fg = "Red",     -- колір тексту
            -- bg = "#928374",     -- фон
            ctermbg = "Red",    -- червоний фон у простому терміналі
            ctermfg = "White", 
            bold = true 
        })
    end,
})



local function load_template_pure_fzf()
  -- Шлях до папки з шаблонами
  local template_dir = vim.fn.expand("~/.config/nvim/templates/")

  -- Перевіряємо, чи існує директорія
  if vim.fn.isdirectory(template_dir) == 0 then
    vim.notify("Папку з шаблонами не знайдено: " .. template_dir, vim.log.levels.ERROR)
    return
  end

  -- ЗАПАМ'ЯТОВУЄМО БУФЕР, де ми стояли (ваш файл .org тощо)
  local original_buf = vim.api.nvim_get_current_buf()

  -- Перевіряємо, чи можна в нього писати
  if not vim.api.nvim_get_option_value("modifiable", { buf = original_buf }) then
    vim.notify("Поточний буфер захищено від запису!", vim.log.levels.WARN)
    return
  end

  -- Тимчасовий файл для результату fzf
  local tmp_file = vim.fn.tempname()

  -- Команда для запуску fzf у терміналі
  local cmd = string.format("cd %s && ls | fzf --prompt='Оберіть шаблон ❯ ' > %s", vim.fn.shellescape(template_dir), tmp_file)

  -- Відкриваємо термінал у спліті знизу (так зручніше, ніж вертикально)
  vim.cmd("botright 10new | terminal " .. cmd)
  local terminal_buf = vim.api.nvim_get_current_buf()
  
  -- Одразу вмикаємо режим вставки для fzf
  vim.cmd("startinsert")

  -- Створюємо автокоманду на закриття буфера ТЕРМІНАЛА
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = terminal_buf,
    once = true,
    callback = function()
      -- Перевіряємо, чи вибрав користувач щось
      if vim.fn.filereadable(tmp_file) == 1 then
        local lines = vim.fn.readfile(tmp_file)
        
        if #lines > 0 and lines[1] ~= "" then
          local selected = lines[1]
          local full_path = template_dir .. selected

          -- Зчитуємо вміст файлу шаблону в таблицю Lua
          local template_lines = vim.fn.readfile(full_path)

          -- БЕЗПЕЧНО вставляємо рядки безпосередньо в оригінальний буфер
          -- {0, 0} означає вставити на самий початок файлу
          vim.api.nvim_buf_set_lines(original_buf, 0, 0, false, template_lines)

          -- Видаляємо порожній рядок в самому кінці оригінального буфера, якщо він там був
          local total_lines = vim.api.nvim_buf_line_count(original_buf)
          if total_lines > 1 then
            local last_line = vim.api.nvim_buf_get_lines(original_buf, -2, -1, false)[1]
            if last_line == "" then
              vim.api.nvim_buf_set_lines(original_buf, -2, -1, false, {})
            end
          end

          vim.notify("Шаблон '" .. selected .. "' успішно застосовано!")
        end
        
        -- Чистимо тимчасовий файл
        vim.fn.delete(tmp_file)
      end
    end,
  })
end

-- Створюємо команду :Template
vim.api.nvim_create_user_command("Template", load_template_pure_fzf, {})

-- Гаряча клавіша
vim.keymap.set("n", "<leader>pt", load_template_pure_fzf, { desc = "Insert template via pure fzf" })
