#!/bin/bash
# ==============================================================================
# Скрипт для быстрого запуска проекта VaultN8N из Docker Hub
#
# Этот скрипт:
# 1. Скачивает необходимый docker-compose.yml из репозитория проекта.
# 2. Проверяет и при необходимости создает/дополняет .env файл.
# 3. Модифицирует docker-compose.yml для использования готового образа с Docker Hub.
# 4. Запускает сервис с помощью docker-compose.
# ==============================================================================

# --- Глобальные переменные ---
REPO_URL="https://raw.githubusercontent.com/avdivo/vault_n8n/main"
DOCKER_IMAGE="avdivo/vault-n8n:latest"
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"

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
    if [ ! -f "$ENV_FILE" ]; then
        touch "$ENV_FILE"
        echo "INFO: Создан новый файл .env."
    fi

    # --- Поиск корректной команды python ---
    PYTHON_CMD="python3"
    if ! command -v $PYTHON_CMD &> /dev/null; then
        PYTHON_CMD="python"
        if ! command -v $PYTHON_CMD &> /dev/null; then
            echo "ERROR: Python не установлен. Пожалуйста, установите Python 3."
            exit 1
        fi
    fi

    # Проверяем наличие AUTH_TOKEN
    AUTH_TOKEN_VALUE=$(grep -E "^AUTH_TOKEN=" "$ENV_FILE" | cut -d '=' -f2)
    if [ -z "$AUTH_TOKEN_VALUE" ]; then
        echo "INFO: AUTH_TOKEN не найден. Генерируется новый..."
        AUTH_TOKEN=$($PYTHON_CMD -c 'import secrets; print(secrets.token_hex(16))')
        echo "AUTH_TOKEN=$AUTH_TOKEN" >> "$ENV_FILE"
        display_token_box "AUTH_TOKEN" "$AUTH_TOKEN" "Сохраните этот токен! Он нужен для доступа к API."
    fi

    # Проверяем наличие ENCRYPTION_KEY
    ENCRYPTION_KEY_VALUE=$(grep -E "^ENCRYPTION_KEY=" "$ENV_FILE" | cut -d '=' -f2)
    if [ -z "$ENCRYPTION_KEY_VALUE" ]; then
        echo "INFO: ENCRYPTION_KEY не найден. Генерируется новый..."
        ENCRYPTION_KEY=$($PYTHON_CMD -c 'import secrets; print(secrets.token_hex(32))')
        echo "ENCRYPTION_KEY=$ENCRYPTION_KEY" >> "$ENV_FILE"
        display_token_box "ENCRYPTION_KEY" "$ENCRYPTION_KEY" "Сохраните этот ключ! Он нужен для шифрования данных. Без него вы потеряете все данные."
    fi
}

# --- Основная логика скрипта ---

echo "--- Установка и запуск VaultN8N ---"

# 1. Проверка наличия необходимых утилит (curl, docker-compose)
if ! command -v curl &> /dev/null || ! command -v docker-compose &> /dev/null; then
    echo "ERROR: Для работы скрипта необходимы curl и docker-compose." >&2
    exit 1
fi

# 2. Скачивание docker-compose.yml
echo "INFO: Скачивание файла docker-compose.yml..."
curl -sSL -o "$COMPOSE_FILE" "$REPO_URL/$COMPOSE_FILE"
if [ $? -ne 0 ]; then
    echo "ERROR: Не удалось скачать docker-compose.yml. Проверьте подключение к интернету." >&2
    exit 1
fi

# 3. Подготовка .env файла
ensure_env_vars
echo "INFO: Файл .env готов."
echo "INFO: Важно! Сохраните сгенерированные токены/ключи из .env файла в безопасном месте."
echo "INFO: Без ENCRYPTION_KEY вы не сможете расшифровать свои секреты!"

# 4. Проверка и подготовка файла базы данных
DB_FILE="secrets.db"
# Проверяем, не является ли 'secrets.db' директорией
if [ -d "$DB_FILE" ]; then
    echo "ОШИБКА: '$DB_FILE' существует, но является директорией." >&2
    echo "Это могло произойти из-за некорректного предыдущего запуска Docker." >&2
    echo "Пожалуйста, удалите эту директорию командой: rm -r $DB_FILE" >&2
    echo "Затем повторно запустите этот скрипт." >&2
    exit 1
fi
# Убедимся, что файл базы данных существует на хосте.
# Если его нет, создаем. Если он есть, touch просто обновит время модификации.
touch "$DB_FILE"

# 5. Модификация docker-compose.yml для использования образа с Docker Hub
# Используем sed для замены блока build на image.
# `sed -i` для in-place редактирования. Добавляем .bak для совместимости с macOS
sed -i.bak "s|build: .|image: $DOCKER_IMAGE|" "$COMPOSE_FILE"
# Удаляем .bak-файл
rm -f "${COMPOSE_FILE}.bak"

echo "INFO: docker-compose.yml настроен для использования образа '$DOCKER_IMAGE'."

# 6. Запуск контейнера
echo "INFO: Скачивание последней версии образа и запуск контейнера..."
docker-compose up -d

# 7. Проверка статуса
if [ $? -eq 0 ]; then
    echo "--- VaultN8N успешно запущен! ---"
    echo "Приложение доступно по адресу http://localhost:8200"
    echo "Документация API (Swagger UI): http://localhost:8200/docs"
    echo "Ваши ключи для доступа сохранены в файле .env в текущей директории."
else
    echo "ERROR: Произошла ошибка при запуске docker-compose. Проверьте логи выше." >&2
fi
