local M = {}

-- Шлях до файлу конфігурації абревіатур
local config_dir = vim.fn.stdpath("config") .. "/awards53"
local config_file = config_dir .. "/abbreviations.json"

-- Дефолтний словник (якщо файл порожній або відсутній)
local default_dictionary = {
  ["3АКого"]   = "3 армійського корпусу",
  ["іменіВМ"]  = "імені князя Володимира Мономаха",
  ["53ди"]     = "53 окремої механізованої бригади",
  ["53да"]     = "53 окрема механізована бригада",
  ["53ді"]     = "53 окремій механізованій бригаді",
}

-- Глобальний кеш для роботи
local dictionary = {}
local keys = {}

-- Завантаження та безпечний парсинг JSON
function M.load_abbreviations()
  -- Створюємо директорію, якщо її немає
  if vim.fn.isdirectory(config_dir) == 0 then
    vim.fn.mkdir(config_dir, "p")
  end

  -- Якщо файлу немає, створюємо з дефолтними значеннями
  if vim.fn.filereadable(config_file) == 0 then
    local f = io.open(config_file, "w")
    if f then
      f:write(vim.json.encode(default_dictionary))
      f:close()
    end
  end

  -- Читаємо файл
  local f = io.open(config_file, "r")
  if not f then
    dictionary = default_dictionary
  else
    local content = f:read("*a")
    f:close()

    -- ЗАХИСТ ВІД ПОМИЛОК СИНТАКСИСУ:
    local success, parsed = pcall(vim.json.decode, content)
    if success and type(parsed) == "table" then
      dictionary = parsed
    else
      -- Якщо користувач зламав JSON, плагін не впаде, а попередить і завантажить дефолт
      vim.notify("[Awards53] Помилка синтаксису в abbreviations.json! Завантажено дефолтні налаштування.", vim.log.levels.WARN)
      dictionary = default_dictionary
    end
  end

  -- Оновлюємо та сортуємо ключі за довжиною (для правильного матчингу)
  keys = {}
  for k in pairs(dictionary) do table.insert(keys, k) end
  table.sort(keys, function(a, b) return #a > #b end)
end

-- Відкриття файлу налаштувань для користувача
function M.edit_config()
  -- Гарантуємо, що файл існує перед відкриттям
  M.load_abbreviations()
  
  -- Відкриваємо файл у новій вкладці (або спліті, як вам зручніше)
  vim.cmd("tabedit " .. vim.fn.fnameescape(config_file))
  
  -- Вмикаємо автокоманду: при збереженні цього JSON налаштування автоматично перезавантажаться в пам'ять
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

-- Реєстрація автокоманди для буфера
function M.register_buffer_abbreviations(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Якщо кеш порожній, робимо первинне завантаження
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

return M
