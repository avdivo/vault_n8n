#!/bin/bash
# ======================================================================================
# Скрипт для автоматической интеграции сервиса VaultN8N в проект kossakovsky/n8n-install.
#
# Назначение:
# Этот скрипт модифицирует конфигурационные файлы существующего развертывания
# n8n-install, чтобы добавить и настроить сервис VaultN8N как "родной"
# компонент системы.
#
# Производимые изменения:
# - Файл .env:
#   - Добавляется переменная VAULTN8N_HOSTNAME для домена сервиса.
#   - Генерируются и добавляются VAULTN8N_AUTH_TOKEN и VAULTN8N_ENCRYPTION_KEY.
#   - Профиль "vaultn8n" добавляется в COMPOSE_PROFILES для активации сервиса.
#   - Сервис "vaultn8n" добавляется в GOST_NO_PROXY для корректной работы сети.
#
# - Файл docker-compose.yml:
#   - Добавляется полная конфигурация сервиса "vaultn8n" с использованием
#     образа avdivo/vault-n8n:latest.
#   - В сервис "caddy" добавляется переменная окружения VAULTN8N_HOSTNAME.
#   - В корневой раздел "volumes" добавляется том "vaultn8n_data" для хранения БД.
#
# - Файл Caddyfile:
#   - Добавляется блок, настраивающий реверс-прокси для домена
#     {$VAULTN8N_HOSTNAME} на внутренний порт контейнера vaultn8n.
#
# Безопасность:
# Скрипт можно безопасно запускать несколько раз. Существующие значения
# и конфигурации не будут перезаписаны.
#
# Требования:
# - Скрипт должен запускаться из корневой директории проекта n8n-install.
#   Пример:
#   cd /path/to/n8n-install
#   bash /path/to/vault_n8n/add_to_kossakovsky-n8n-install.sh
# ======================================================================================

set -e # Прекратить выполнение при любой ошибке

# --- Переменные ---
PROJECT_ROOT=$(pwd)
ENV_FILE="${PROJECT_ROOT}/.env"
DOCKER_COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
CADDY_FILE="${PROJECT_ROOT}/Caddyfile"
SERVICE_NAME="vault-n8n"
PROFILE_NAME="vault-n8n"
DOCKER_IMAGE="avdivo/vault-n8n:latest"

# --- Функции ---
log_info() {
    echo "[INFO] $1"
}

log_success() {
    echo "✅ $1"
}

log_warn() {
    echo "⚠️ $1"
}

# --- Функция для форматированного вывода токенов в рамке ---
display_token_box() {
    local label="$1"
    local token="$2"
    local msg="$3"
    local border_char="="
    local padding_char=" "

    local max_width=80
    local label_len=${#label}
    local token_len=${#token}
    local msg_len=${#msg}
    local content_len=$((label_len + token_len + 3)) 
    
    local line_len=$((max_width - 2)) 
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


# --- Начало ---
log_info "Запуск скрипта для интеграции VaultN8N в n8n-install..."
log_info "Целевая директория: ${PROJECT_ROOT}"



# 1. Конфигурация файла .env
log_info "Проверка и обновление файла ${ENV_FILE}..."

# Запрос домена для VaultN8N
DEFAULT_HOSTNAME="${SERVICE_NAME}.$(grep -oP '(?<=^DOMAIN=).*' $ENV_FILE | head -n 1)"
CURRENT_HOSTNAME=$(grep "^VAULTN8N_HOSTNAME=" "${ENV_FILE}" | cut -d'=' -f2)

if [ -z "$CURRENT_HOSTNAME" ]; then
    read -p "Введите домен для VaultN8N (по умолчанию: ${DEFAULT_HOSTNAME}): " USER_HOSTNAME
    VAULTN8N_HOSTNAME="${USER_HOSTNAME:-$DEFAULT_HOSTNAME}"
    echo "" >> "${ENV_FILE}"
    echo "# --- VaultN8N Settings ---" >> "${ENV_FILE}"
    echo "VAULTN8N_HOSTNAME=${VAULTN8N_HOSTNAME}" >> "${ENV_FILE}"
    log_success "Добавлена переменная VAULTN8N_HOSTNAME: ${VAULTN8N_HOSTNAME}."
else
    log_info "Переменная VAULTN8N_HOSTNAME уже существует: ${CURRENT_HOSTNAME}. Используется текущее значение."
    VAULTN8N_HOSTNAME="$CURRENT_HOSTNAME"
fi

# Генерация и добавление VAULTN8N_AUTH_TOKEN
if ! grep -q "^VAULTN8N_AUTH_TOKEN=" "${ENV_FILE}"; then
    TOKEN=$(openssl rand -hex 16)
    echo "VAULTN8N_AUTH_TOKEN=\"$TOKEN\"" >> "${ENV_FILE}"
    display_token_box "VAULTN8N_AUTH_TOKEN" "$TOKEN" "Сохраните этот токен! Он нужен для доступа к API VaultN8N."
else
    log_info "Переменная VAULTN8N_AUTH_TOKEN уже существует."
fi

# Генерация и добавление VAULTN8N_ENCRYPTION_KEY
if ! grep -q "^VAULTN8N_ENCRYPTION_KEY=" "${ENV_FILE}"; then
    KEY=$(openssl rand -hex 32)
    echo "VAULTN8N_ENCRYPTION_KEY=\"$KEY\"" >> "${ENV_FILE}"
    display_token_box "VAULTN8N_ENCRYPTION_KEY" "$KEY" "Сохраните этот ключ! Он нужен для шифрования данных VaultN8N."
else
    log_info "Переменная VAULTN8N_ENCRYPTION_KEY уже существует."
fi

# Добавление профиля в COMPOSE_PROFILES
if ! grep -q "COMPOSE_PROFILES=.*${PROFILE_NAME}" "${ENV_FILE}"; then
    if grep -q "^COMPOSE_PROFILES=" "${ENV_FILE}"; then
        sed -i "s/^\(COMPOSE_PROFILES=.*\)\$/\1,${PROFILE_NAME}/
" "${ENV_FILE}"
    else
        echo "COMPOSE_PROFILES=${PROFILE_NAME}" >> "${ENV_FILE}"
    fi
    log_success "Профиль '${PROFILE_NAME}' добавлен в COMPOSE_PROFILES."
else
    log_info "Профиль '${PROFILE_NAME}' уже есть в COMPOSE_PROFILES."
fi

# Добавление сервиса в GOST_NO_PROXY (если используется)
if grep -q "^GOST_NO_PROXY=" "${ENV_FILE}"; then
    if ! grep -q "GOST_NO_PROXY=.*${SERVICE_NAME}" "${ENV_FILE}"; then
        sed -i "s/^\(GOST_NO_PROXY=.*\)\$/\1,${SERVICE_NAME}/
" "${ENV_FILE}"
        log_success "Сервис '${SERVICE_NAME}' добавлен в GOST_NO_PROXY."
    else
        log_info "Сервис '${SERVICE_NAME}' уже есть в GOST_NO_PROXY."
    fi
fi

# 2. Обновление docker-compose.yml
log_info "Проверка и обновление файла ${DOCKER_COMPOSE_FILE}..."

# Добавление сервиса vaultn8n, если его нет
if ! grep -q "container_name: ${SERVICE_NAME}" "${DOCKER_COMPOSE_FILE}"; then
    # Вставляем перед первым top-level 'volumes:'
    SERVICE_BLOCK="
  ${SERVICE_NAME}:
    image: ${DOCKER_IMAGE}
    container_name: ${SERVICE_NAME}
    profiles: [\"${PROFILE_NAME}\"]
    restart: unless-stopped
    volumes:
      - vault-n8n_data:/data
    environment:
      - AUTH_TOKEN=\\\\\${VAULTN8N_AUTH_TOKEN}
      - ENCRYPTION_KEY=\\\\\${VAULTN8N_ENCRYPTION_KEY}
      - DATABASE_PATH=/data/secrets.db
"
    sed -i "/^volumes:/i\$SERVICE_BLOCK" "${DOCKER_COMPOSE_FILE}"
    log_success "Сервис '${SERVICE_NAME}' добавлен в docker-compose.yml."
else
    log_info "Сервис '${SERVICE_NAME}' уже существует в docker-compose.yml."
fi

# Добавление тома vault-n8n_data, если его нет
if ! grep -q "vault-n8n_data:" "${DOCKER_COMPOSE_FILE}"; then
    echo "  vault-n8n_data:" >> "${DOCKER_COMPOSE_FILE}"
    log_success "Том 'vault-n8n_data' добавлен в docker-compose.yml."
else
    log_info "Том 'vault-n8n_data' уже существует в docker-compose.yml."
fi


# Добавление переменной VAULTN8N_HOSTNAME в секцию environment сервиса caddy
if ! grep -q "VAULTN8N_HOSTNAME: \\\${VAULTN8N_HOSTNAME}" "${DOCKER_COMPOSE_FILE}"; then
    sed -i '/caddy:/,/environment:/s/^\s*environment:/&\n      - VAULTN8N_HOSTNAME=${VAULTN8N_HOSTNAME}/' "${DOCKER_COMPOSE_FILE}"
    log_success "Переменная VAULTN8N_HOSTNAME добавлена в окружение сервиса caddy."
else
    log_info "Переменная VAULTN8N_HOSTNAME уже есть в окружении сервиса caddy."
fi


# 3. Обновление Caddyfile
log_info "Проверка и обновление файла ${CADDY_FILE}..."

if ! grep -q "{\\\\\$\\\${VAULTN8N_HOSTNAME}}" "${CADDY_FILE}"; then
    echo "" >> "${CADDY_FILE}"
    echo "# VaultN8N Service" >> "${CADDY_FILE}"
    echo "{\\\\\$\\\${VAULTN8N_HOSTNAME}} {" >> "${CADDY_FILE}"
    echo "    reverse_proxy ${SERVICE_NAME}:8000" >> "${CADDY_FILE}"
    echo "}" >> "${CADDY_FILE}"
    log_success "Блок для '${SERVICE_NAME}' добавлен в Caddyfile."
else
    log_info "Блок для '${SERVICE_NAME}' уже существует в Caddyfile."
fi

echo ""
log_info "-------------------------------------------------"
log_info "Скрипт успешно завершен!"
log_info "Что дальше:"
log_info "1. Если вы не использовали домен по умолчанию, убедитесь, что он корректно настроен в DNS."
log_info "2. Сохраните ваши VAULTN8N_AUTH_TOKEN и VAULTN8N_ENCRYPTION_KEY в надежном месте."
log_info "3. Перезапустите проект командой: docker-compose up -d"
log_info "-------------------------------------------------"
