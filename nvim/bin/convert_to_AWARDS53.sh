#!/usr/bin/env bash

if [ $# -eq 0 ]; then
    echo "Помилка: Не вказано вхідні файли!"
    echo "Використання: $(basename "$0") файл1.odt [файл2.odt ...]"
    exit 1
fi

set -u
set -o pipefail

CONVERTED_FILES=()

for INPUT_FILE in "$@"; do
    if [ ! -f "$INPUT_FILE" ]; then
        echo "Попередження: Файл '$INPUT_FILE' не існує, пропускаємо."
        continue
    fi

    FILENAME=$(basename -- "$INPUT_FILE")
    BASE_NAME="${FILENAME%.*}"
    EXTENSION="${FILENAME##*.}"
    DIR_NAME=$(dirname -- "$INPUT_FILE")

    PANDOC_INPUT="$INPUT_FILE"
    IS_TEMPORARY_DOCX=0

    if [[ "${EXTENSION,,}" == "doc" ]]; then
        echo "Виявлено застарілий формат .doc. Конвертую в .docx..."

        PANDOC_INPUT="$DIR_NAME/${BASE_NAME}.docx"

        if ! libreoffice --headless \
            --convert-to docx \
            --outdir "$DIR_NAME" \
            "$INPUT_FILE" >/dev/null 2>&1; then

            echo "Помилка: не вдалося конвертувати '$INPUT_FILE' у .docx"
            continue
        fi

        if [ ! -f "$PANDOC_INPUT" ]; then
            echo "Помилка: LibreOffice не створив '$PANDOC_INPUT'"
            continue
        fi

        IS_TEMPORARY_DOCX=1
    fi

    OUTPUT_FILE="$DIR_NAME/${BASE_NAME}.txt"

    if pandoc "$PANDOC_INPUT" \
        -t plain \
        -o "$OUTPUT_FILE" \
        -L /dev/stdin <<'EOF'
local function trim(s)
  return s:gsub("^%s+", ""):gsub("%s+$", "")
end


local function get_cell_text(blocks)
  if not blocks or #blocks == 0 then
    return ""
  end

  local parts = {}

  for _, block in ipairs(blocks) do
    local text = pandoc.utils.stringify(block)
    text = trim(text)

    if text ~= "" then
      table.insert(parts, text)
    end
  end

  return table.concat(parts, "\n")
end


function Table(tbl)
  local result = {}
  local first_row = true

  -- Функція додавання однієї строки таблиці
  local function add_row(row)
    local cell_texts = {}

    for _, cell in ipairs(row.cells) do
      -- Використовуємо get_cell_text замість pandoc.utils.stringify
      local text = get_cell_text(cell.contents)
      table.insert(cell_texts, text)
    end

    local row_text = table.concat(cell_texts, "\n::\n")

    -- Роздільник між картками (рядками)
    if not first_row then
      table.insert(result, pandoc.Para({
        pandoc.Str("===")
      }))
    end

    table.insert(result, pandoc.Para({
      pandoc.Str(row_text)
    }))

    first_row = false
  end

  -- 1. Спочатку обробляємо строки з HEAD (шапка)
  if tbl.head and tbl.head.rows then
    for _, row in ipairs(tbl.head.rows) do
      add_row(row)
    end
  end

  -- 2. Потім звичайне тіло таблиці
  if tbl.bodies then
    for _, body in ipairs(tbl.bodies) do
      if body.body then
        for _, row in ipairs(body.body) do
          add_row(row)
        end
      end
    end
  end

  return result
end

function Pandoc(doc)

  local want = "* AWARDS53"
  local found = false

  for _, block in ipairs(doc.blocks) do
    local text = pandoc.utils.stringify(block)

    if trim(text) == want then
      found = true
      break
    end
  end

  if not found then
    table.insert(doc.blocks, 1, pandoc.Para({
      pandoc.Str("*"),
      pandoc.Space(),
      pandoc.Str("AWARDS53")
    }))
  end

  return doc
end
EOF
    then
        echo "Успішно конвертовано: $OUTPUT_FILE"
        CONVERTED_FILES+=("$OUTPUT_FILE")
    else
        echo "Сталася помилка під час конвертації: $INPUT_FILE"
    fi

    if [ "$IS_TEMPORARY_DOCX" -eq 1 ] && [ -f "$PANDOC_INPUT" ]; then
        rm -- "$PANDOC_INPUT"
    fi
done

if [ ${#CONVERTED_FILES[@]} -gt 1 ]; then
    echo "----------------------------------------"
    read -r -p "Бажаєте об'єднати усі конвертовані в один? (y/n): " ANSWER

    if [[ "$ANSWER" =~ ^[YyДд]$ ]]; then

        FIRST_DIR=$(dirname -- "${CONVERTED_FILES[0]}")
        FINAL_COMBINED="$FIRST_DIR/combined_awards.txt"

        if [ -e "$FINAL_COMBINED" ]; then
            echo "Помилка: файл '$FINAL_COMBINED' вже існує."
            exit 1
        fi

        cp -- "${CONVERTED_FILES[0]}" "$FINAL_COMBINED"

        for ((i=1; i<${#CONVERTED_FILES[@]}; i++)); do
            printf '===\n' >> "$FINAL_COMBINED"
            sed '/^\* AWARDS53$/d' \
                "${CONVERTED_FILES[i]}" >> "$FINAL_COMBINED"
        done

        rm -- "${CONVERTED_FILES[@]}"

        echo "Готово! Загальний файл збережено: $FINAL_COMBINED"
    else
        echo "Об'єднання скасовано. Проміжні файли залишено."
    fi
fi
