#!/bin/bash
# ==============================================================================
# Скрипт для запуска проекта в режиме разработки
#
# Этот скрипт:
# 1. Проверяет и при необходимости создает/дополняет .env файл.
# 2. Собирает Docker-образ из локальных исходников.
# 3. Запускает сервис с помощью docker-compose.
# ==============================================================================

# --- Функция для проверки и генерации переменных окружения ---
ensure_env_vars() {
    ENV_FILE=".env"
    
    # Создаем .env, если он не существует
    if [ ! -f "$ENV_FILE" ]; then
        touch "$ENV_FILE"
        echo "INFO: Создан новый файл .env."
    fi

    # Проверяем наличие AUTH_TOKEN
    if ! grep -q -E "^AUTH_TOKEN=" "$ENV_FILE"; then
        echo "INFO: AUTH_TOKEN не найден. Генерируется новый..."
        # Генерируем токен с помощью Python, так как он есть в зависимостях
        AUTH_TOKEN=$(python -c 'import secrets; print(secrets.token_hex(16))')
        echo "AUTH_TOKEN=$AUTH_TOKEN" >> "$ENV_FILE"
        echo "INFO: Новый AUTH_TOKEN добавлен в .env."
    fi

    # Проверяем наличие ENCRYPTION_KEY
    if ! grep -q -E "^ENCRYPTION_KEY=" "$ENV_FILE"; then
        echo "INFO: ENCRYPTION_KEY не найден. Генерируется новый..."
        ENCRYPTION_KEY=$(python -c 'import secrets; print(secrets.token_hex(32))')
        echo "ENCRYPTION_KEY=$ENCRYPTION_KEY" >> "$ENV_FILE"
        echo "INFO: Новый ENCRYPTION_KEY добавлен в .env."
    fi
}

# --- Основная логика скрипта ---

echo "--- Запуск VaultN8N в режиме разработки ---"

# 1. Подготовка .env файла
ensure_env_vars
echo "INFO: Файл .env готов."

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
    echo "Приложение доступно по адресу http://localhost:8000 (если порт не изменен)"
else
    echo "ERROR: Произошла ошибка при запуске docker-compose. Проверьте логи выше."
fi
