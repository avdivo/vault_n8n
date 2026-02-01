#!/bin/bash
# ==============================================================================
# Скрипт для интеграции сервиса vault-n8n в проект n8n-install.
#
# Этот скрипт:
# 1. Генерирует необходимые секреты (AUTH_TOKEN, ENCRYPTION_KEY).
# 2. Добавляет переменные окружения в .env файл.
# 3. Создает отдельный docker-compose.vault-n8n.yml в новой папке ./vault-n8n.
# 4. Модифицирует Caddyfile для предоставления доступа к сервису извне.
# 5. Создает и делает исполняемым управляющий скрипт vault.sh.
# 6. Выводит сгенерированные данные и УПРОЩЕННЫЕ инструкции по запуску.
#
# Скрипт идемпотентен: безопасен для повторного запуска.
# ==============================================================================

set -e # Exit immediately if a command exits with a non-zero status.

# --- Глобальные переменные ---
SERVICE_NAME="vault-n8n"
SERVICE_DIR="./$SERVICE_NAME"
COMPOSE_FILE_PATH="$SERVICE_DIR/docker-compose.$SERVICE_NAME.yml"
CADDY_FILE="Caddyfile"
ENV_FILE=".env"
WRAPPER_SCRIPT_NAME="vault.sh"

# --- Функция для вывода сообщений ---
log_info() {
    echo "INFO: $1"
}

log_success() {
    echo "✅ SUCCESS: $1"
}

log_error() {
    echo "❌ ERROR: $1" >&2
    exit 1
}

# --- Функция для форматированного вывода данных в рамке ---
display_generated_data_box() {
    local title=""
    local url="$2"
    local token_label="$3"
    local token_value="$4"
    local key_label="$5"
    local key_value="$6"
    local start_command="$7"
    local stop_command="$8"

    local border_char="="
    local max_width=80
    local border_line=$(printf "%${max_width}s" "" | tr " " "$border_char")

    echo ""
    echo "$border_line"
    printf "| %-76s |\n" "✅ Интеграция $title завершена!"
    echo "$border_line"
    printf "| %-76s |\n" " "
    printf "| %-76s |\n" "URL для доступа: $url"
    printf "| %-76s |\n" " "
    printf "| %-76s |\n" "Сохраните эти данные! Они не будут показаны снова:"
    printf "| %-76s |\n" "  -> $token_label: $token_value"
    printf "| %-76s |\n" "  -> $key_label: $key_value"
    printf "| %-76s |\n" " "
    printf "| %-76s |\n" "Команды для управления контейнером:"
    printf "| %-76s |\n" "  Запуск: $start_command"
    printf "| %-76s |\n" "  Остановка: $stop_command"
    printf "| %-76s |\n" " "
    echo "$border_line"
    echo ""
}

# --- Основная логика скрипта ---
main() {
    log_info "Запуск интеграции сервиса '$SERVICE_NAME'..."

    # 1. Проверка наличия .env и Caddyfile
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Файл '$ENV_FILE' не найден. Запустите скрипт из корневой директории проекта n8n-install."
    fi
    if [ ! -f "$CADDY_FILE" ]; then
        log_error "Файл '$CADDY_FILE' не найден. Запустите скрипт из корневой директории проекта n8n-install."
    fi

    # 2. Определение домена
    local domain_name
    # Source .env file to get USER_DOMAIN_NAME in a subshell to avoid polluting current shell
    domain_name=$( (set -a; source $ENV_FILE 2>/dev/null; echo $USER_DOMAIN_NAME) )

    if [ -z "$domain_name" ]; then
        log_info "Переменная USER_DOMAIN_NAME не найдена в .env. Будет использован 'localhost'."
        domain_name="localhost"
    fi
    local service_hostname="$SERVICE_NAME.$domain_name"
    log_info "Сервис будет доступен по адресу: $service_hostname"

    # 3. Создание директории (безопасно для повторного запуска)
    log_info "Проверка и создание директории '$SERVICE_DIR/data'..."
    mkdir -p "$SERVICE_DIR/data"
    log_success "Директория '$SERVICE_DIR/data' готова."

    # 4. Обновление .env файла (с проверкой на существование)
    log_info "Проверка и добавление переменных для '$SERVICE_NAME' в '$ENV_FILE'..."
    
    # Добавляем заголовок секции, если его еще нет
    if ! grep -q "# --- Переменные для сервиса $SERVICE_NAME ---" "$ENV_FILE"; then
        echo "" >> "$ENV_FILE"
        echo "# --- Переменные для сервиса $SERVICE_NAME ---" >> "$ENV_FILE"
    fi
    
    # Проверяем и добавляем каждую переменную индивидуально
    if ! grep -q "VAULT_N8N_HOSTNAME=" "$ENV_FILE"; then
        echo "VAULT_N8N_HOSTNAME=$service_hostname" >> "$ENV_FILE"
        log_success "Добавлена переменная VAULT_N8N_HOSTNAME."
    fi

    if ! grep -q "VAULT_N8N_AUTH_TOKEN=" "$ENV_FILE"; then
        local auth_token=$(openssl rand -hex 16)
        echo "VAULT_N8N_AUTH_TOKEN=$auth_token" >> "$ENV_FILE"
        log_success "Сгенерирована и добавлена переменная VAULT_N8N_AUTH_TOKEN."
    fi

    if ! grep -q "VAULT_N8N_ENCRYPTION_KEY=" "$ENV_FILE"; then
        local encryption_key=$(openssl rand -hex 32)
        echo "VAULT_N8N_ENCRYPTION_KEY=$encryption_key" >> "$ENV_FILE"
        log_success "Сгенерирована и добавлена переменная VAULT_N8N_ENCRYPTION_KEY."
    fi
    
    # Добавляем футер секции, если его еще нет
    if ! grep -q "# --- Конец секции $SERVICE_NAME ---" "$ENV_FILE"; then
        echo "# --- Конец секции $SERVICE_NAME ---" >> "$ENV_FILE"
    fi

    # 5. Создание docker-compose файла (с healthcheck и logging)
    log_info "Создание файла '$COMPOSE_FILE_PATH'..."
    cat << EOF > "$COMPOSE_FILE_PATH"
services:
  $SERVICE_NAME:
    image: avdivo/vault-n8n:latest
    container_name: $SERVICE_NAME
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "1m"
        max-file: "1"
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8000/docs || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
    environment:
      - AUTH_TOKEN=\${VAULT_N8N_AUTH_TOKEN}
      - ENCRYPTION_KEY=\${VAULT_N8N_ENCRYPTION_KEY}
      - DATABASE_PATH=/data/secrets.db
    volumes:
      - ./data:/data
    networks:
      - localai_default

networks:
  localai_default:
    external: true
EOF
    log_success "Файл '$COMPOSE_FILE_PATH' успешно создан."
    
    # 6. Модификация Caddyfile (с проверкой на существование)
    if grep -q "reverse_proxy $SERVICE_NAME:8000" "$CADDY_FILE"; then
        log_info "Конфигурация для '$SERVICE_NAME' уже существует в $CADDY_FILE. Пропускаем..."
    else
        log_info "Обновление файла '$CADDY_FILE'..."
        # Create the text to be inserted. Note the escaped dollar sign for Caddy's variable.
        CADDY_INSERT=$(cat <<END_CADDY

# $SERVICE_NAME
{\$VAULT_N8N_HOSTNAME} {
    reverse_proxy $SERVICE_NAME:8000
}

END_CADDY
)
        # Use awk to insert the block before the line containing "# SearXNG"
        if grep -q "# SearXNG" "$CADDY_FILE"; then
            awk -v block="$CADDY_INSERT" '
            /# SearXNG/ && !p {
                print block;
                p=1
            }
            {
                print
            }' "$CADDY_FILE" > "${CADDY_FILE}.tmp" && mv "${CADDY_FILE}.tmp" "$CADDY_FILE"
            log_success "Конфигурация для '$SERVICE_NAME' добавлена в '$CADDY_FILE'."
        else
            log_info "Не удалось найти блок '# SearXNG', добавляем конфигурацию в конец файла."
            printf '%s\n' "$CADDY_INSERT" >> "$CADDY_FILE"
            log_success "Конфигурация для '$SERVICE_NAME' добавлена в конец '$CADDY_FILE'."
        fi
    fi

    # 7. Создание управляющего скрипта-обертки
    log_info "Создание управляющего скрипта ./$WRAPPER_SCRIPT_NAME для удобства..."
    cat << 'EOW' > "./$WRAPPER_SCRIPT_NAME"
#!/bin/bash
# Управляющий скрипт для сервиса vault-n8n
# Пробрасывает все аргументы в docker-compose с правильными флагами.
docker compose --env-file ./.env -f ./vault-n8n/docker-compose.vault-n8n.yml "$@"
EOW
    
    chmod +x "./$WRAPPER_SCRIPT_NAME"
    log_success "Скрипт ./$WRAPPER_SCRIPT_NAME успешно создан и сделан исполняемым."


    # 8. Вывод финального отчета
    log_info "Загрузка актуальных данных из .env для отчета..."
    # Загружаем переменные из .env в subshell, чтобы получить актуальные значения
    # на случай, если они уже были в файле
    local final_auth_token=$(grep "VAULT_N8N_AUTH_TOKEN=" "$ENV_FILE" | cut -d '=' -f2)
    local final_encryption_key=$(grep "VAULT_N8N_ENCRYPTION_KEY=" "$ENV_FILE" | cut -d '=' -f2)
    local final_hostname=$(grep "VAULT_N8N_HOSTNAME=" "$ENV_FILE" | cut -d '=' -f2)

    local protocol="https"
    if [[ "$final_hostname" == *"localhost"* ]]; then
        protocol="http"
    fi
    
    display_generated_data_box \
        "$SERVICE_NAME" \
        "$protocol://$final_hostname" \
        "VAULT_N8N_AUTH_TOKEN" "$final_auth_token" \
        "VAULT_N8N_ENCRYPTION_KEY" "$final_encryption_key" \
        "./$WRAPPER_SCRIPT_NAME up -d" \
        "./$WRAPPER_SCRIPT_NAME down"

    log_info "Не забудьте перезапустить Caddy, чтобы применить изменения: docker compose up -d --force-recreate caddy"
}

# Вызов основной функции
main