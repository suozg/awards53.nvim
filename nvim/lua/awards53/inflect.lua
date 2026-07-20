local M = {}

-- 1. Допоміжні функції через vim.fn (працюють у будь-якій версії Neovim)
local function utf8_lower(str)
  return vim.fn.tolower(str)
end

local function utf8_upper(str)
  return vim.fn.toupper(str)
end

local function utf8_len(str)
  -- vim.fn.strcharlen рахує символи (літери), а не байти
  return vim.fn.strcharlen(str) or 0
end

-- Перевіряємо, чи слово написане ВЕЛИКИМИ ЛІТЕРАМИ
local function is_uppercase(word)
  return word == utf8_upper(word) and utf8_len(word) > 2
end

-- Безпечно відрізає N символів з кінця і додає новий суфікс
local function replace_ending(word, chars_to_drop, new_suffix)
  local len = utf8_len(word)
  if len <= chars_to_drop then return word end
  
  -- vim.fn.strcharpart(рядок, старт_індікс, довжина). Індексація з 0!
  local root = vim.fn.strcharpart(word, 0, len - chars_to_drop)
  return root .. new_suffix
end

-- 2. Визначення статі за по батькові
local function detect_gender(text)
  local lower_text = utf8_lower(text)
  if lower_text:match("ovna") or lower_text:match("овна") or lower_text:match("івна") or lower_text:match("ївна") then
    return "female"
  elseif lower_text:match("ovych") or lower_text:match("ович") or lower_text:match("евич") or lower_text:match("євич") then
    return "male"
  end
  return "unknown"
end

-- 3. Відмінювання окремого слова (Знахідний відмінок / Accusative)
local function inflect_word(word, is_male, is_surname)
  if not word or word == "" then return "" end

  local lower = utf8_lower(word)
  local is_caps = is_uppercase(word)
  local len = utf8_len(word)

  -- Отримуємо останні літери безпечно для UTF-8 (індекси з нуля)
  local last_1 = vim.fn.strcharpart(lower, len - 1, 1)
  local last_2 = vim.fn.strcharpart(lower, len - 2, 2)

  -- А. Спільні правила для імен та прізвищ на -а / -я (Микола -> Миколу, Ілля -> Іллю)
  if last_1 == "а" then
    return replace_ending(word, 1, is_caps and "У" or "у")
  elseif last_1 == "я" then
    return replace_ending(word, 1, is_caps and "Ю" or "ю")
  end

  -- Б. Правила для ЧОЛОВІКІВ (Імена та Прізвища)
  if is_male then
    if is_surname then
      -- Чоловічі прізвища на -о (Шевченко -> Шевченка)
      if last_1 == "о" then
        return replace_ending(word, 1, is_caps and "А" or "а")
      -- Чоловічі прізвища на -ий / -ій (Балінський -> Балінського)
      elseif last_2 == "ий" then
        return replace_ending(word, 2, is_caps and "ОГО" or "ого")
      elseif last_2 == "ій" then
        return replace_ending(word, 2, is_caps and "ЬОГО" or "ього")
      end
    else
      -- Чоловічі імена на -о (Павло -> Павла)
      if last_1 == "о" then
        return replace_ending(word, 1, is_caps and "А" or "а")
      -- Імена на -ій (Сергій -> Сергія, Валерій -> Валерія)
      elseif last_2 == "ій" then
        return replace_ending(word, 2, is_caps and "ІЯ" or "ія")
      -- Імена на м'який знак або -й (Ігор/Василь)
      elseif last_1 == "ь" or last_1 == "й" then
        return replace_ending(word, 1, is_caps and "Я" or "я")
      -- Імена на приголосну (Іван -> Івана)
      elseif lower:match("[бвгґджзклмнпрстфхцчшщ]$") then
        return word .. (is_caps and "А" or "а")
      end
    end
  end

  -- Якщо під правила не підпало
  return word
end

function M.to_accusative(text)
  if not text or text == "" then return "" end

  text = text:gsub("^%s*(.-)%s*$", "%1")
  local gender = detect_gender(text)
  local is_male = (gender ~= "female")

  local words = {}
  for word in string.gmatch(text, "[^%s]+") do
    table.insert(words, word)
  end

  local result = {}
  for i, word in ipairs(words) do
    local is_surname = (i == 1)
    table.insert(result, (inflect_word(word, is_male, is_surname)))
  end

  return table.concat(result, " ")
end

return M
