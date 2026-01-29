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

# --- Функция для проверки и генерации переменных окружения ---
ensure_env_vars() {
    if [ ! -f "$ENV_FILE" ]; then
        touch "$ENV_FILE"
        echo "INFO: Создан новый файл .env."
    fi

    if ! grep -q -E "^AUTH_TOKEN=" "$ENV_FILE"; then
        echo "INFO: AUTH_TOKEN не найден. Генерируется новый..."
        AUTH_TOKEN=$(python -c 'import secrets; print(secrets.token_hex(16))')
        echo "AUTH_TOKEN=$AUTH_TOKEN" >> "$ENV_FILE"
        echo "INFO: Новый AUTH_TOKEN добавлен в .env."
    fi

    if ! grep -q -E "^ENCRYPTION_KEY=" "$ENV_FILE"; then
        echo "INFO: ENCRYPTION_KEY не найден. Генерируется новый..."
        ENCRYPTION_KEY=$(python -c 'import secrets; print(secrets.token_hex(32))')
        echo "ENCRYPTION_KEY=$ENCRYPTION_KEY" >> "$ENV_FILE"
        echo "INFO: Новый ENCRYPTION_KEY добавлен в .env."
    fi
}

# --- Основная логика скрипта ---

echo "--- Установка и запуск VaultN8N ---"

# 1. Проверка наличия необходимых утилит (curl, docker-compose, python)
if ! command -v curl &> /dev/null || ! command -v docker-compose &> /dev/null || ! command -v python &> /dev/null; then
    echo "ERROR: Для работы скрипта необходимы curl, docker-compose и python."
    exit 1
fi

# 2. Скачивание docker-compose.yml
echo "INFO: Скачивание файла docker-compose.yml..."
curl -sSL -o "$COMPOSE_FILE" "$REPO_URL/$COMPOSE_FILE"
if [ $? -ne 0 ]; then
    echo "ERROR: Не удалось скачать docker-compose.yml. Проверьте подключение к интернету."
    exit 1
fi

# 3. Подготовка .env файла
ensure_env_vars
echo "INFO: Файл .env готов."

# 4. Модификация docker-compose.yml для использования образа с Docker Hub
# Используем sed для замены блока build на image.
# `sed -i` для in-place редактирования. Добавляем .bak для совместимости с macOS
sed -i.bak "s|build: .|image: $DOCKER_IMAGE|" "$COMPOSE_FILE"
# Удаляем .bak-файл
rm -f "${COMPOSE_FILE}.bak"

echo "INFO: docker-compose.yml настроен для использования образа '$DOCKER_IMAGE'."

# 5. Запуск контейнера
echo "INFO: Скачивание последней версии образа и запуск контейнера..."
docker-compose up -d

# 6. Проверка статуса
if [ $? -eq 0 ]; then
    echo "--- VaultN8N успешно запущен! ---"
    echo "Приложение доступно по адресу http://localhost:8000 (если порт не изменен)"
    echo "Ваши ключи для доступа сохранены в файле .env в текущей директории."
else
    echo "ERROR: Произошла ошибка при запуске docker-compose. Проверьте логи выше."
fi
