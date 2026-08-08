#!/bin/bash

SEARCH_TERM="$1"
DB_FILE="$2"

if [ -z "$SEARCH_TERM" ] || [ -z "$DB_FILE" ]; then
    echo "Помилка: Не вказано пошуковий термін або файл бази даних." >&2
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "Помилка: Файл бази даних не існує: $DB_FILE" >&2
    exit 1
fi

if ! command -v sqlcipher >/dev/null 2>&1; then
    echo "Помилка: Утиліта sqlcipher не встановлена в системі." >&2
    exit 1
fi

# Читаємо пароль бази даних через stdin (аналогічно до GPG-пароля у search.sh)
read -r DB_PASSWORD

if [ -z "$DB_PASSWORD" ]; then
    echo "Помилка: Пароль до бази даних не передано." >&2
    exit 1
fi

# Переводимо пошуковий термін у верхній регістр для коректного пошуку кирилицею
SEARCH_UPPER="${SEARCH_TERM^^}"

sqlcipher "$DB_FILE" <<EOF
PRAGMA key = '$DB_PASSWORD';
PRAGMA cipher_compatibility = 3;
PRAGMA kdf_iter = 64000;

.mode csv
.separator " "

SELECT 
p.id, 
    p.name, 
    p.inn, 
    p.rank, 
    p.unit, 
    a.denotation, 
    m.date_decree, 
    m.decree, 
    m.number_meed, 
    m.consignment_note
FROM meed m
LEFT JOIN personality p ON p.id = m.id_personality
LEFT JOIN award a ON a.id = m.id_award
WHERE p.name LIKE '${SEARCH_UPPER}' || '%'
   OR p.inn LIKE '${SEARCH_UPPER}' || '%';
EOF

# Очищуємо пароль у пам'яті
unset DB_PASSWORD
