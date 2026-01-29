#!/bin/bash
# ==============================================================================
# Скрипт для запуска проекта в режиме разработки
#
# Этот скрипт:
# 1. Проверяет и при необходимости создает/дополняет .env файл.
# 2. Собирает Docker-образ из локальных исходников.
# 3. Запускает сервис с помощью docker-compose.
# ==============================================================================

# --- Функция для форматированного вывода токенов в рамке ---
display_token_box() {
    local label="$1"
    local token="$2"
    local msg="$3"
    local border_char="="
    local padding_char=" "

    # Определяем ширину рамки
    local max_width=80
    local label_len=${#label}
    local token_len=${#token}
    local msg_len=${#msg}
    local content_len=$((label_len + token_len + 3)) # "Label: Token"
    
    local line_len=$((max_width - 2)) # Длина содержимого внутри рамки
    if [ "$content_len" -gt "$line_len" ]; then
        line_len=$content_len
    fi

    local border=$(printf "%*s" "$line_len" | tr " " "$border_char")
    local padding=$(printf "%*s" "$line_len" | tr " " "$padding_char")

    echo ""
    echo "$border_char$border$border_char"
    echo "$border_char$padding$border_char"
    printf "%s %s %s\n" "$border_char" "$(printf "%-${line_len}s" "$label: $token")" "$border_char"
    echo "$border_char$padding$border_char"
    printf "%s %s %s\n" "$border_char" "$(printf "%-${line_len}s" "$msg")" "$border_char"
    echo "$border_char$padding$border_char"
    echo "$border_char$border$border_char"
    echo ""
}

# --- Функция для проверки и генерации переменных окружения ---
ensure_env_vars() {
    ENV_FILE=".env"
    
    # Создаем .env, если он не существует
    if [ ! -f "$ENV_FILE" ]; then
        touch "$ENV_FILE"
        echo "INFO: Создан новый файл .env."
    fi

    # Проверяем наличие AUTH_TOKEN
    AUTH_TOKEN_VALUE=$(grep -E "^AUTH_TOKEN=" "$ENV_FILE" | cut -d '=' -f2)
    if [ -z "$AUTH_TOKEN_VALUE" ]; then
        echo "INFO: AUTH_TOKEN не найден. Генерируется новый..."
        AUTH_TOKEN=$(python -c 'import secrets; print(secrets.token_hex(16))')
        echo "AUTH_TOKEN=$AUTH_TOKEN" >> "$ENV_FILE"
        display_token_box "AUTH_TOKEN" "$AUTH_TOKEN" "Сохраните этот токен! Он нужен для доступа к API."
    fi

    # Проверяем наличие ENCRYPTION_KEY
    ENCRYPTION_KEY_VALUE=$(grep -E "^ENCRYPTION_KEY=" "$ENV_FILE" | cut -d '=' -f2)
    if [ -z "$ENCRYPTION_KEY_VALUE" ]; then
        echo "INFO: ENCRYPTION_KEY не найден. Генерируется новый..."
        ENCRYPTION_KEY=$(python -c 'import secrets; print(secrets.token_hex(32))')
        echo "ENCRYPTION_KEY=$ENCRYPTION_KEY" >> "$ENV_FILE"
        display_token_box "ENCRYPTION_KEY" "$ENCRYPTION_KEY" "Сохраните этот ключ! Он нужен для шифрования данных. Без него вы потеряете все данные."
    fi
}

# --- Основная логика скрипта ---

echo "--- Запуск VaultN8N в режиме разработки ---"

# 1. Подготовка .env файла
ensure_env_vars
echo "INFO: Файл .env готов."
echo "INFO: Важно! Сохраните сгенерированные токены/ключи из .env файла в безопасном месте."
echo "INFO: Без ENCRYPTION_KEY вы не сможете расшифровать свои секреты!"

# 2. Проверка наличия docker-compose
if ! command -v docker-compose &> /dev/null; then
    echo "ERROR: docker-compose не найден. Пожалуйста, установите Docker и docker-compose."
    exit 1
fi

# 3. Сборка и запуск контейнера
echo "INFO: Сборка и запуск Docker-контейнера... (это может занять некоторое время)"
docker-compose up --build -d

# 4. Проверка статуса
if [ $? -eq 0 ]; then
    echo "--- VaultN8N успешно запущен! ---"
    echo "Приложение доступно по адресу http://localhost:8200"
    echo "Документация API (Swagger UI): http://localhost:8200/docs"
else
    echo "ERROR: Произошла ошибка при запуске docker-compose. Проверьте логи выше."
fi
