#!/bin/bash

SEARCH_TERM="$1"
SEARCH_DIR="$2"

if [ -z "$SEARCH_TERM" ] || [ -z "$SEARCH_DIR" ]; then
    echo "Помилка: Не вказано термін або папку для пошуку." >&2
    exit 1
fi

if [ ! -d "$SEARCH_DIR" ]; then
    echo "Помилка: Папка не існує: $SEARCH_DIR" >&2
    exit 1
fi

TEMP_DIR=$(mktemp -d -p /dev/shm 2>/dev/null || mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Читаємо пароль один раз у змінну всередині скрипта, щоб безпечно передавати його будь-яку кількість разів
read -r GPG_PASSWORD

if command -v rg >/dev/null 2>&1; then
    SEARCH_CMD='rg -i -F'
else
    SEARCH_CMD='grep -a -i -F'
fi

SEARCH_DIR_ABS=$(eval echo "$SEARCH_DIR")

# ВИКЛЮЧАЄМО .swp та тимчасові файли на кшталт .* за допомогою ! -name ".*" та ! -name "*.swp"
mapfile -d '' FILES < <(
    find -L "$SEARCH_DIR_ABS" -type f \
        ! -name ".*" \
        ! -name "*.swp" \
        \( \
            -iname "*.gpg" -o -iname "*.txt" -o -iname "*.csv" -o -iname "*.log" \
            -o -iname "*.doc*" -o -iname "*.xls*" -o -iname "*.odt" -o -iname "*.ods" \
            -o -iname "*.pdf" \
        \) -print0 2>/dev/null
)

HAS_ERROR=0
MATCH_FOUND=0

for FILE in "${FILES[@]}"; do
    TARGET_FILE="$FILE"
    DECRYPTED_FILE=""

    if [[ "$FILE" =~ \.gpg$ ]]; then
        DECRYPTED_FILE="$TEMP_DIR/dec_$(basename "${FILE%.gpg}")"
        
        GPG_OUTPUT=$(printf '%s\n' "$GPG_PASSWORD" | gpg --quiet --batch --yes \
            --pinentry-mode loopback \
            --passphrase-fd 0 \
            --output "$DECRYPTED_FILE" \
            --decrypt "$FILE" 2>&1)
        
        if [ $? -ne 0 ]; then
            # Пропускаємо біті/биті файти тихо або фіксуємо помилку, якщо це справжній документ
            continue
        fi
        TARGET_FILE="$DECRYPTED_FILE"
    fi

    MATCHES=""
    EXT="${TARGET_FILE##*.}"

    case "${EXT,,}" in
        txt|csv|log)
            MATCHES=$($SEARCH_CMD "$SEARCH_TERM" "$TARGET_FILE" 2>/dev/null)
            ;;
        pdf)
            if command -v pdftotext >/dev/null 2>&1; then
                MATCHES=$(pdftotext "$TARGET_FILE" - 2>/dev/null | $SEARCH_CMD "$SEARCH_TERM" 2>/dev/null)
            fi
            ;;
        *)
            if command -v soffice >/dev/null 2>&1; then
                soffice --headless --convert-to txt:"Text" \
                    "$TARGET_FILE" --outdir "$TEMP_DIR" >/dev/null 2>&1
                CONV_FILE="$TEMP_DIR/$(basename "${TARGET_FILE%.*}.txt")"
                if [ -f "$CONV_FILE" ]; then
                    MATCHES=$($SEARCH_CMD "$SEARCH_TERM" "$CONV_FILE" 2>/dev/null)
                    rm -f "$CONV_FILE"
                fi
            fi
            ;;
    esac

    if [ -n "$MATCHES" ]; then
        MATCH_FOUND=1
        while IFS= read -r match_line; do
            echo "[$FILE] $match_line"
        done <<< "$MATCHES"
    fi

    [ -n "$DECRYPTED_FILE" ] && rm -f "$DECRYPTED_FILE"
done

# Очищуємо пароль у пам'яті
unset GPG_PASSWORD
