#!/bin/bash
# ======================================================================================
# Скрипт для автоматической интеграции сервиса VaultN8N в проект kossakovsky/n8n-install.
#
# Этот скрипт является идемпотентным и может быть запущен несколько раз.
# ======================================================================================

set -e # Прекратить выполнение при любой ошибке
set -o pipefail # Прекратить выполнение, если команда в конвейере завершается с ошибкой

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

fail() {
    echo "ОШИБКА: $1" >&2
    exit 1
}

# Функция для форматированного вывода итоговой информации
display_summary_box() {
    local hostname="$1"
    local token="$2"
    local key="$3"

    # Подготовка строк
    local line1="Домен сервиса: ${hostname}"
    local line2="AUTH_TOKEN: ${token}"
    local line3="ENCRYPTION_KEY: ${key}"
    local line4="Обязательно сохраните токен и ключ в надежном месте!"

    # Определение максимальной длины для рамки
    local max_len=0
    for line in "$line1" "$line2" "$line3" "$line4"; do
        if ((${#line} > max_len)); then
            max_len=${#line}
        fi
    done

    local border_char="="
    local padding_char=" "
    local line_len=$((max_len + 4)) # Добавляем отступы

    local border=$(printf "%*s" "$line_len" | tr " " "$border_char")
    local padding_line="$border_char$(printf "%*s" $((line_len - 2)) | tr " " "$padding_char")$border_char"

    # Вывод рамки
    echo ""
    echo "$border"
    echo "$padding_line"
    printf "%s %-*s %s\n" "$border_char" $((line_len - 4)) "$line1" "$border_char"
    printf "%s %-*s %s\n" "$border_char" $((line_len - 4)) "$line2" "$border_char"
    printf "%s %-*s %s\n" "$border_char" $((line_len - 4)) "$line3" "$border_char"
    echo "$padding_line"
    printf "%s %-*s %s\n" "$border_char" $((line_len - 4)) "$line4" "$border_char"
    echo "$padding_line"
    echo "$border"
    echo ""
}


# --- Начало ---
log_info "Запуск скрипта для интеграции VaultN8N..."

# --- 1. Конфигурация файла .env ---
log_info "Проверка и обновление файла .env..."
[ -f "$ENV_FILE" ] || fail "Файл .env не найден. Убедитесь, что вы находитесь в корневой директории проекта n8n-install."

# Установка домена
DOMAIN=$(grep -E '^USER_DOMAIN_NAME=' "${ENV_FILE}" | cut -d'=' -f2- | tr -d '[:space:]"' || true)
[ -n "$DOMAIN" ] || fail "Переменная USER_DOMAIN_NAME не найдена или пуста в файле .env. Пожалуйста, установите ее."
VAULTN8N_HOSTNAME="${SERVICE_NAME}.${DOMAIN}"
if ! grep -q "^VAULTN8N_HOSTNAME=" "${ENV_FILE}"; then
    echo "" >> "${ENV_FILE}"
    echo "# --- VaultN8N Settings ---" >> "${ENV_FILE}"
    echo "VAULTN8N_HOSTNAME=${VAULTN8N_HOSTNAME}" >> "${ENV_FILE}"
fi

# Генерация и/или получение токенов
FINAL_TOKEN=$(grep -E '^VAULTN8N_AUTH_TOKEN=' "${ENV_FILE}" | cut -d'=' -f2- | tr -d '"' || true)
if [ -z "$FINAL_TOKEN" ]; then
    FINAL_TOKEN=$(openssl rand -hex 16)
    echo "VAULTN8N_AUTH_TOKEN=\"$FINAL_TOKEN\"" >> "${ENV_FILE}"
fi

FINAL_KEY=$(grep -E '^VAULTN8N_ENCRYPTION_KEY=' "${ENV_FILE}" | cut -d'=' -f2- | tr -d '"' || true)
if [ -z "$FINAL_KEY" ]; then
    FINAL_KEY=$(openssl rand -hex 32)
    echo "VAULTN8N_ENCRYPTION_KEY=\"$FINAL_KEY\"" >> "${ENV_FILE}"
fi

# Добавление профиля
if ! grep -q "COMPOSE_PROFILES=.*${PROFILE_NAME}" "${ENV_FILE}"; then
    if grep -q "^COMPOSE_PROFILES=" "${ENV_FILE}"; then
        sed -i "s/^\(COMPOSE_PROFILES=.*\)\$/\1,${PROFILE_NAME}/" "${ENV_FILE}"
    else
        echo "COMPOSE_PROFILES=${PROFILE_NAME}" >> "${ENV_FILE}"
    fi
fi

# Добавление в NO_PROXY
if grep -q "^GOST_NO_PROXY=" "${ENV_FILE}" && ! grep -q "GOST_NO_PROXY=.*${SERVICE_NAME}" "${ENV_FILE}"; then
    sed -i "s/^\(GOST_NO_PROXY=.*\)\$/\1,${SERVICE_NAME}/" "${ENV_FILE}"
fi
log_success "Файл .env сконфигурирован."

# --- 2. Обновление docker-compose.yml ---
log_info "Проверка и обновление файла docker-compose.yml..."
# Добавление сервиса
if ! grep -q "container_name: ${SERVICE_NAME}" "${DOCKER_COMPOSE_FILE}"; then
    SERVICE_BLOCK="
  ${SERVICE_NAME}:
    image: ${DOCKER_IMAGE}
    container_name: ${SERVICE_NAME}
    profiles: [\"${PROFILE_NAME}\"]
    restart: unless-stopped
    volumes:
      - vault-n8n_data:/data
    environment:
      AUTH_TOKEN: \${VAULTN8N_AUTH_TOKEN}
      ENCRYPTION_KEY: \${VAULTN8N_ENCRYPTION_KEY}
      DATABASE_PATH: /data/secrets.db"

    TMP_SERVICE_BLOCK_FILE=$(mktemp)
    printf '%s' "${SERVICE_BLOCK}" > "${TMP_SERVICE_BLOCK_FILE}"
    sed -i -e "/^services:/r ${TMP_SERVICE_BLOCK_FILE}" "${DOCKER_COMPOSE_FILE}"
    rm "${TMP_SERVICE_BLOCK_FILE}"
fi

# Добавление тома
if ! grep -q "^\s*vault-n8n_data:" "${DOCKER_COMPOSE_FILE}"; then
    sed -i '/^volumes:/a \ \ vault-n8n_data:' "${DOCKER_COMPOSE_FILE}"
fi

# Добавление переменной в caddy
if ! grep -q "VAULTN8N_HOSTNAME:" "${DOCKER_COMPOSE_FILE}"; then
    sed -i '/^\s*caddy:/,/^\s*environment:/s/^\(\s*environment:\)/\1\n      VAULTN8N_HOSTNAME: ${VAULTN8N_HOSTNAME}/' "${DOCKER_COMPOSE_FILE}"
fi
log_success "Файл docker-compose.yml сконфигурирован."

# --- 3. Обновление Caddyfile ---
log_info "Проверка и обновление файла Caddyfile..."
if ! grep -q "{\$VAULTN8N_HOSTNAME}" "${CADDY_FILE}"; then
    echo "" >> "${CADDY_FILE}"
    echo "# VaultN8N Service" >> "${CADDY_FILE}"
    echo "{\$VAULTN8N_HOSTNAME} {" >> "${CADDY_FILE}"
    echo "    reverse_proxy ${SERVICE_NAME}:8000" >> "${CADDY_FILE}"
    echo "}" >> "${CADDY_FILE}"
fi
log_success "Файл Caddyfile сконфигурирован."

# --- Финальный отчет ---
log_info "Интеграция успешно завершена!"
display_summary_box "$VAULTN8N_HOSTNAME" "$FINAL_TOKEN" "$FINAL_KEY"
