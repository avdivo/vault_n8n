#!/bin/bash
# ==============================================================================
# Скрипт для установки и запуска проекта VaultN8N из Docker Hub.
#
# Этот скрипт:
# 1. Создает директорию 'vault_n8n' для инкапсуляции файлов проекта.
# 2. Проверяет и создает .env файл в ТЕКУЩЕЙ директории (родительской).
# 3. Скачивает docker-compose.yml в директорию 'vault_n8n'.
# 4. Модифицирует docker-compose.yml для использования .env из родительской
#    директории и готового образа с Docker Hub.
# 5. Запускает сервис с помощью docker-compose из директории 'vault_n8n'.
# ==============================================================================

set -e # Прерывать выполнение при любой ошибке

# --- Глобальные переменные ---
REPO_URL="https://raw.githubusercontent.com/avdivo/vault_n8n/main"
DOCKER_IMAGE="avdivo/vault-n8n:latest"
PROJECT_DIR="vault_n8n"
COMPOSE_FILE_NAME="docker-compose.yml"
COMPOSE_FILE_PATH="$PROJECT_DIR/$COMPOSE_FILE_NAME"
DB_FILE_PATH="$PROJECT_DIR/secrets.db"
ENV_FILE=".env" # В родительской директории

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
    # Эта функция работает с .env в ТЕКУЩЕЙ директории
    if [ ! -f "$ENV_FILE" ]; then
        touch "$ENV_FILE"
        echo "INFO: Создан новый файл .env в текущей директории."
    fi
    PYTHON_CMD="python3"
    if ! command -v $PYTHON_CMD &> /dev/null; then
        PYTHON_CMD="python"
        if ! command -v $PYTHON_CMD &> /dev/null; then
            echo "ОШИБКА: Python не установлен. Пожалуйста, установите Python 3." >&2
            exit 1
        fi
    fi
    # grep "|| true" - чтобы скрипт не падал, если файл пустой
    AUTH_TOKEN_VALUE=$(grep -E "^AUTH_TOKEN=" "$ENV_FILE" | cut -d '=' -f2 || true)
    if [ -z "$AUTH_TOKEN_VALUE" ]; then
        echo "INFO: AUTH_TOKEN не найден в $ENV_FILE. Генерируется новый..."
        AUTH_TOKEN=$($PYTHON_CMD -c 'import secrets; print(secrets.token_hex(16))')
        echo "AUTH_TOKEN=$AUTH_TOKEN" >> "$ENV_FILE"
        display_token_box "AUTH_TOKEN" "$AUTH_TOKEN" "Сохраните этот токен! Он нужен для доступа к API."
    fi
    ENCRYPTION_KEY_VALUE=$(grep -E "^ENCRYPTION_KEY=" "$ENV_FILE" | cut -d '=' -f2 || true)
    if [ -z "$ENCRYPTION_KEY_VALUE" ]; then
        echo "INFO: ENCRYPTION_KEY не найден в $ENV_FILE. Генерируется новый..."
        ENCRYPTION_KEY=$($PYTHON_CMD -c 'import secrets; print(secrets.token_hex(32))')
        echo "ENCRYPTION_KEY=$ENCRYPTION_KEY" >> "$ENV_FILE"
        display_token_box "ENCRYPTION_KEY" "$ENCRYPTION_KEY" "Сохраните этот ключ! Он нужен для шифрования данных."
    fi
}

# --- Основная логика скрипта ---
main() {
    echo "--- Установка и запуск VaultN8N ---"

    # 1. Проверка наличия утилит
    if ! command -v curl &> /dev/null || ! command -v docker-compose &> /dev/null; then
        echo "ОШИБКА: Для работы скрипта необходимы утилиты 'curl' и 'docker-compose'." >&2
        exit 1
    fi

    # 2. Создание директории проекта
    mkdir -p "$PROJECT_DIR"
    echo "INFO: Файлы проекта будут размещены в директории '$PROJECT_DIR'."

    # 3. Подготовка .env файла в родительской директории
    ensure_env_vars
    echo "INFO: Файл '$ENV_FILE' в текущей директории готов."
    
    # 4. Скачивание docker-compose.yml
    if [ ! -f "$COMPOSE_FILE_PATH" ]; then
        echo "INFO: Скачивание файла docker-compose.yml..."
        curl -sSL -o "$COMPOSE_FILE_PATH" "$REPO_URL/$COMPOSE_FILE_NAME"
    else
        echo "INFO: Файл '$COMPOSE_FILE_PATH' уже существует, скачивание пропущено."
    fi
    
    # 5. Проверка и подготовка файла базы данных
    if [ -d "$DB_FILE_PATH" ]; then
        echo "ОШИБКА: '$DB_FILE_PATH' существует, но является директорией." >&2
        echo "Пожалуйста, удалите эту директорию командой: rm -r $DB_FILE_PATH" >&2
        exit 1
    fi
    touch "$DB_FILE_PATH"

    # 6. Модификация docker-compose.yml
    # Используем sed для замены блока build на image и корректировки пути к .env.
    # Флаг -i.bak создает резервную копию для совместимости с macOS.
    sed -i.bak \
        -e "s|build: .|image: $DOCKER_IMAGE|" \
        -e "s|- ./.env|- ../.env|" \
        "$COMPOSE_FILE_PATH"
    rm -f "${COMPOSE_FILE_PATH}.bak" # Удаляем .bak-файл
    echo "INFO: Файл docker-compose.yml настроен для запуска."

    # 7. Запуск контейнера из директории проекта
    echo "INFO: Запуск Docker-контейнера... (это может занять некоторое время)"
    (cd "$PROJECT_DIR" && docker-compose up -d)

    echo "--- VaultN8N успешно запущен! ---"
    echo "Приложение доступно по адресу http://localhost:8200"
    echo "Документация API (Swagger UI): http://localhost:8200/docs"
    echo "Директория проекта: $PROJECT_DIR"
    echo "Файл конфигурации: $ENV_FILE"
}

# Вызов основной функции с передачей всех аргументов
main "$@"