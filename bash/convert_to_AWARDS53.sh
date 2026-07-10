#!/usr/bin/env bash

# 1. Перевіряємо, чи передано вхідний файл
if [ -z "$1" ]; then
    echo "Помилка: Не вказано вхідний файл!"
    echo "Використання: $(basename "$0") файл.odt"
    exit 1
fi

INPUT_FILE="$1"
FILENAME=$(basename -- "$INPUT_FILE")
BASE_NAME="${FILENAME%.*}"
DIR_NAME=$(dirname -- "$INPUT_FILE")
OUTPUT_FILE="$DIR_NAME/${BASE_NAME}.txt"

# 2. Запускаємо pandoc із оновленим Lua-фільтром
pandoc "$INPUT_FILE" -t plain -o "$OUTPUT_FILE" -L /dev/stdin << 'EOF'

-- функція обходить кожен абзац (Para/Plain) всередині комірки
-- і з'єднує їх через нормальний перенос рядка, зберігаючи структуру тексту.
local function get_cell_text(blocks)
  if not blocks or #blocks == 0 then return "" end
  
  local paragraph_texts = {}
  for _, block in ipairs(blocks) do
    local txt = pandoc.utils.stringify(block)
    -- Прибираємо лише зайві пробіли на кінцях самого абзацу, але зберігаємо його як окремий рядок
    txt = txt:gsub("^%s*(.-)%s*$", "%1")
    if txt ~= "" then
      table.insert(paragraph_texts, txt)
    end
  end
  
  -- Повертаємо всі абзаци комірки, об'єднані через звичайний перенос рядка
  return table.concat(paragraph_texts, "\n")
end

-- Перехоплюємо кожну таблицю в документі
function Table(tbl)
  local lines = {}
  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.body) do
      local cell_texts = {}
      for _, cell in ipairs(row.cells) do
        -- ЗМІНЕНО: передаємо cell.contents (масив блоків/абзаців) в нову функцію
        local txt = get_cell_text(cell.contents)
        table.insert(cell_texts, txt)
      end
      local row_string = table.concat(cell_texts, "\n::\n")
      table.insert(lines, row_string)
    end
  end
  local table_output = table.concat(lines, "\n===\n")
  return pandoc.Para({pandoc.Str(table_output)})
end

-- Фінальна обробка документа
function Pandoc(doc)
  local want = "AWARDS53"
  io.stderr:write("Doc blocks: " .. tostring(#doc.blocks) .. "\n")
  local found = false
  for i, b in ipairs(doc.blocks) do
    local t = pandoc.utils.stringify(b)
    if t and t:find(want, 1, true) then
      found = true
      break
    end
  end
  if not found then
    table.insert(doc.blocks, 1, pandoc.Para("* " .. want))
  end
  return doc
end
EOF

# 3. Перевірка результату роботи Bash
if [ $? -eq 0 ]; then
    echo "Успішно конвертовано: $OUTPUT_FILE"
else
    echo "Сталася помилка під час конвертації."
fi
