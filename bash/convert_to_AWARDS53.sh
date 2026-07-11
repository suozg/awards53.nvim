#!/usr/bin/env bash

# 1. Перевіряємо, чи передано хоча б один вхідний файл
if [ $# -eq 0 ]; then
    echo "Помилка: Не вказано вхідні файли!"
    echo "Використання: $(basename "$0") файл1.odt [файл2.odt ...]"
    exit 1
fi

# Масив для зберігання шляхів до успішно створених текстових файлів
CONVERTED_FILES=()

# 2. Цикл обробки кожного файлу
for INPUT_FILE in "$@"; do
    if [ ! -f "$INPUT_FILE" ]; then
        echo "Попередження: Файл '$INPUT_FILE' не існує, пропускаємо."
        continue
    fi

    FILENAME=$(basename -- "$INPUT_FILE")
    BASE_NAME="${FILENAME%.*}"
    EXTENSION="${FILENAME##*.}"
    DIR_NAME=$(dirname -- "$INPUT_FILE")
    
    # Тимчасова змінна для роботи pandoc
    PANDOC_INPUT="$INPUT_FILE"
    IS_TEMPORARY_DOCX=false

    # АВТОКОНВЕРТАЦІЯ СТАРОГО .doc В .docx
    if [[ "${EXTENSION,,}" == "doc" ]]; then
        echo "Виявлено застарілий формат .doc. Конвертую в .docx за допомогою LibreOffice..."
        
        # Конвертуємо у той самий каталог
        libreoffice --headless --convert-to docx --outdir "$DIR_NAME" "$INPUT_FILE" > /dev/null 2>&1
        
        # Перемикаємо pandoc на роботу з новим тимчасовим файлом
        PANDOC_INPUT="$DIR_NAME/${BASE_NAME}.docx"
        IS_TEMPORARY_DOCX=true
    fi

    OUTPUT_FILE="$DIR_NAME/${BASE_NAME}.txt"

   # Запускаємо pandoc із Lua-фільтром
    pandoc "$INPUT_FILE" -t plain -o "$OUTPUT_FILE" -L /dev/stdin << 'EOF'
local function get_cell_text(blocks)
  if not blocks or #blocks == 0 then return "" end
  local paragraph_texts = {}
  for _, block in ipairs(blocks) do
    local txt = pandoc.utils.stringify(block)
    txt = txt:gsub("^%s*(.-)%s*$", "%1")
    if txt ~= "" then table.insert(paragraph_texts, txt) end
  end
  return table.concat(paragraph_texts, "\n")
end

function Table(tbl)
  local lines = {}
  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.body) do
      local cell_texts = {}
      for _, cell in ipairs(row.cells) do
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

    if [ $? -eq 0 ]; then
        echo "Успішно конвертовано: $OUTPUT_FILE"
        CONVERTED_FILES+=("$OUTPUT_FILE")
    else
        echo "Сталася помилка під час конвертації: $INPUT_FILE"
    fi

    # Видаляємо тимчасовий .docx, щоб не засмічувати систему
    if [ "$IS_TEMPORARY_DOCX" = true ] && [ -f "$PANDOC_INPUT" ]; then
        rm "$PANDOC_INPUT"
    fi
done


# 3. Интерактивный запрос на объединение (если конвертировано больше 1 файла)
if [ ${#CONVERTED_FILES[@]} -gt 1 ]; then
    echo "----------------------------------------"
    read -p "Желаете объединить все конвертированные файлы в один? (y/n): " ANSWER

    if [[ "$ANSWER" =~ ^[YyДд]$ ]]; then
        # Формируем имя для совместного файла (на основе первого файла)
        FIRST_DIR=$(dirname -- "${CONVERTED_FILES[0]}")
        FINAL_COMBINED="$FIRST_DIR/combined_awards.txt"
        
        echo "Объединяю файлы в '$FINAL_COMBINED'..."

        # Копируем первый файл полностью (вместе с его первой меткой * AWARDS53)
        cp "${CONVERTED_FILES[0]}" "$FINAL_COMBINED"

        # Все остальные файлы добавляем в цикл
        for ((i=1; i<${#CONVERTED_FILES[@]}; i++)); do
            # 1. Сначала добавляем разделитель карточек перед контентом следующего файла
            echo "===" >> "$FINAL_COMBINED"
            
            # 2. Затем добавляем сам файл, вырезая из него дублирующуюся метку * AWARDS53
            sed '/^\* AWARDS53/d' "${CONVERTED_FILES[i]}" >> "$FINAL_COMBINED"
        done

        # Удаляем промежуточные файлы
        echo "Удаляю промежуточные файлы..."
        rm "${CONVERTED_FILES[@]}"
        
        echo "Готово! Общий файл сохранен: $FINAL_COMBINED"
    else
        echo "Объединение отменено. Промежуточные файлы оставлены."
    fi
fi
