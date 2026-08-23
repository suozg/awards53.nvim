local M = {}

-- Шлях до файлу конфігурації абревіатур
local config_dir = vim.fn.stdpath("config") .. "/awards53"
local config_file = config_dir .. "/abbreviations.json"

-- Глобальний кеш для роботи
local dictionary = {}
local keys = {}

-- Завантаження та безпечний парсинг JSON
function M.load_abbreviations()
  -- Створюємо директорію, якщо її немає
  if vim.fn.isdirectory(config_dir) == 0 then
    vim.fn.mkdir(config_dir, "p")
  end

  -- Якщо файлу немає, створюємо порожній JSON-об'єкт
  if vim.fn.filereadable(config_file) == 0 then
    local f = io.open(config_file, "w")
    if f then
      f:write("{}")
      f:close()
    end
  end

  -- Читаємо файл
  local f = io.open(config_file, "r")
  if f then
    local content = f:read("*a")
    f:close()

    -- ЗАХИСТ ВІД ПОМИЛОК СИНТАКСИСУ:
    local success, parsed = pcall(vim.json.decode, content)
    if success and type(parsed) == "table" then
      dictionary = parsed
    else
      vim.notify("[Awards53] Помилка синтаксису в abbreviations.json!", vim.log.levels.WARN)
      dictionary = {}
    end
  else
    dictionary = {}
  end

  -- Оновлюємо та сортуємо ключі за довжиною (для правильного матчингу)
  keys = {}
  for k in pairs(dictionary) do table.insert(keys, k) end
  table.sort(keys, function(a, b) return #a > #b end)
end

-- Відкриття файлу налаштувань для користувача
function M.edit_config()
  M.load_abbreviations()
  
  vim.cmd("tabedit " .. vim.fn.fnameescape(config_file))
  
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_create_autocmd("BufWritePost", {
    buffer = bufnr,
    once = true,
    callback = function()
      M.load_abbreviations()
      vim.notify("[Awards53] Абревіатури успішно оновлено!", vim.log.levels.INFO)
    end,
  })
end

-- Функція для застосування абревіатур до тексту (при форматуванні)
function M.apply_abbreviations(text)
  if #keys == 0 then
    M.load_abbreviations()
  end

  for _, key in ipairs(keys) do
    local value = dictionary[key]
    text = text:gsub(vim.pesc(key), value)
  end
  return text
end

-- Інтерактивне меню вибору через vim.ui.select
function M.select_and_insert()
  if #keys == 0 then
    M.load_abbreviations()
  end

  if vim.tbl_isempty(dictionary) then
    vim.notify("[Awards53] Словник абревіатур порожній! Додайте їх у abbreviations.json", vim.log.levels.WARN)
    return
  end

  local items = {}
  for _, k in ipairs(keys) do
    table.insert(items, string.format("%s ➔ %s", k, dictionary[k]))
  end

  vim.ui.select(items, {
    prompt = "Виберіть абревіатуру для вставки:",
  }, function(choice)
    if not choice then return end
    local key = choice:match("^(.-)%s+➔")
    if key and dictionary[key] then
      local val = dictionary[key]
      vim.api.nvim_put({val}, "c", true, true)
    end
  end)
end

-- Реєстрація автокоманди для буфера (автозаміна під час введення тексту)
function M.register_buffer_abbreviations(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if #keys == 0 then
    M.load_abbreviations()
  end

  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = bufnr,
    callback = function()
      local row, col0 = unpack(vim.api.nvim_win_get_cursor(0))
      local line = vim.api.nvim_get_current_line()
      local before = line:sub(1, col0)

      for _, key in ipairs(keys) do
        if before:sub(-#key) == key then
          local value = dictionary[key]
          local start_col = col0 - #key
          local end_col = col0

          vim.api.nvim_buf_set_text(bufnr, row-1, start_col, row-1, end_col, { value })
          vim.api.nvim_win_set_cursor(0, { row, start_col + #value })

          return
        end
      end
    end,
  })
end

-- Функція збереження словника у файл з перехопленням помилок
local function save_dictionary()
  local f = io.open(config_file, "w")
  if f then
    f:write(vim.json.encode(dictionary))
    f:close()
    -- Оновлюємо ключі після збереження
    keys = {}
    for k in pairs(dictionary) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return #a > #b end)
    vim.notify("[Awards53] Абревіатури успішно збережено!", vim.log.levels.INFO)
  else
    vim.notify("[Awards53] Помилка збереження файлу абревіатур!", vim.log.levels.ERROR)
  end
end

-- Інтерактивне меню керування (додавання / редагування / видалення)
function M.manage_abbreviations()
  if #keys == 0 then
    M.load_abbreviations()
  end

  local options = {
    "➕ Додати нову абревіатуру",
    "✏️ Редагувати існуючу абревіатуру",
    "🗑️ Видалити існуючу абревіатуру",
    "👀 Переглянути список",
  }

  vim.ui.select(options, {
    prompt = "Керування абревіатурами:",
  }, function(choice)
    if not choice then return end

    if choice:match("Додати") then
      vim.ui.input({ prompt = "Введіть коротку абревіатуру (ключ): " }, function(new_key)
        if not new_key or new_key == "" then return end
        
        vim.ui.input({ prompt = "Введіть повний текст для '" .. new_key .. "': " }, function(new_val)
          if not new_val or new_val == "" then return end

          dictionary[new_key] = new_val
          save_dictionary()
        end)
      end)

    elseif choice:match("Редагувати") then
      if vim.tbl_isempty(dictionary) then
        vim.notify("[Awards53] Словник порожній!", vim.log.levels.WARN)
        return
      end

      local items = {}
      for _, k in ipairs(keys) do
        table.insert(items, string.format("%s ➔ %s", k, dictionary[k]))
      end

      vim.ui.select(items, {
        prompt = "Виберіть абревіатуру для редагування:",
      }, function(edit_choice)
        if not edit_choice then return end
        local old_key = edit_choice:match("^(.-)%s+➔")
        
        if old_key and dictionary[old_key] then
          local old_val = dictionary[old_key]
          
          -- 1. Редагуємо сам ключ (абрвіатуру)
          vim.ui.input({ 
            prompt = "Змінити ключ (абрвіатуру): ",
            default = old_key,
          }, function(new_key)
            if not new_key or new_key == "" then return end

            -- 2. Редагуємо повний текст
            vim.ui.input({ 
              prompt = "Змінити текст для '" .. new_key .. "': ",
              default = old_val,
            }, function(updated_val)
              if not updated_val or updated_val == "" then return end

              -- Якщо ключ змінився, видаляємо старий запис
              if new_key ~= old_key then
                dictionary[old_key] = nil
              end

              -- Зберігаємо під новим (або оновленим) ключем
              dictionary[new_key] = updated_val
              save_dictionary()
            end)
          end)
        end
      end)
      
    elseif choice:match("Видалити") then
      if vim.tbl_isempty(dictionary) then
        vim.notify("[Awards53] Словник порожній!", vim.log.levels.WARN)
        return
      end

      local items = {}
      for _, k in ipairs(keys) do
        table.insert(items, string.format("%s ➔ %s", k, dictionary[k]))
      end

      vim.ui.select(items, {
        prompt = "Виберіть абревіатуру для видалення:",
      }, function(del_choice)
        if not del_choice then return end
        local key_to_del = del_choice:match("^(.-)%s+➔")
        if key_to_del and dictionary[key_to_del] then
          dictionary[key_to_del] = nil
          save_dictionary()
        end
      end)

    elseif choice:match("Переглянути") then
      if vim.tbl_isempty(dictionary) then
        vim.notify("[Awards53] Словник порожній!", vim.log.levels.WARN)
        return
      end

      local items = {}
      for _, k in ipairs(keys) do
        table.insert(items, string.format("• [%s] = %s", k, dictionary[k]))
      end

      vim.ui.select(items, {
        prompt = "Поточний список абревіатур (Натисніть Esc для виходу):",
      }, function() end)
    end
  end)
end

return M
