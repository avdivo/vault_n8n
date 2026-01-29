# VaultN8N

VaultN8N - это минималистичное серверное приложение для безопасного хранения, выдачи и удаления секретов (паролей, токенов и т.п.) через HTTP API. Оно разработано для интеграции с [n8n](https://n8n.io/) в одной Docker-сети, позволяя n8n взаимодействовать с секретами через `Request node` или внешний прокси.

Проект создан с упором на простоту, предсказуемость, минимальные зависимости и небольшой размер Docker-образа, не претендуя на роль полноценного корпоративного хранилища секретов.

## Оглавление

- [Общие технические требования](#общие-технические-требования)
- [Структура проекта](#структура-проекта)
- [Установка и запуск](#установка-и-запуск)
- [Конфигурация](#конфигурация)
- [Использование API](#использование-api)
  - [Авторизация](#авторизация)
  - [Примеры Curl](#примеры-curl)
    - [Добавление/Обновление одного секрета](#добавлениеобновление-одного-секрета)
    - [Массовое добавление/обновление секретов](#массовое-добавлениеобновление-секретов)
    - [Получение секретов](#получение-секретов)
    - [Удаление секретов](#удаление-секретов)
- [Интеграция с n8n](#интеграция-с-n8n)
- [Тестирование](#тестирование)
- [Советы по безопасности и эксплуатации](#советы-по-безопасности-и-эксплуатации)

## Общие технические требования

- **Язык**: Python 3.11
- **Web-фреймворк**: FastAPI
- **База данных**: SQLite, fts5 (файловая, key-value логика)
- **ORM**: Не используется (прямая работа с `sqlite3`)
- **Шифрование**: AES-256-GCM
- **Тесты**: `pytest`
- **Контейнеризация**: Docker

## Структура проекта

```
vault_n8n/
├── app/
│   ├── main.py           # Точка входа FastAPI
│   ├── config.py         # Загрузка и валидация .env
│   ├── models.py         # Pydantic-модели
│   ├── crypto.py         # Шифрование / дешифрование
│   ├── db.py             # Работа с SQLite
│   ├── auth.py           # Авторизация по токену
│   ├── api/
│   │   └── routes.py     # API эндпоинты
│   └── utils.py          # Вспомогательные функции
├── tests/                # pytest-тесты
├── Dockerfile
├── .env.example
└── README.md
```

## Установка и запуск

### С использованием Docker Compose (рекомендуется)

1.  **Создайте `.env` файл**: Скопируйте `.env.example` в `.env` и укажите ваши значения `AUTH_TOKEN` и `ENCRYPTION_KEY`.
    ```bash
    cp .env.example .env
    # Откройте .env и заполните переменные
    ```
    *   `AUTH_TOKEN`: Используется для авторизации API.
    *   `ENCRYPTION_KEY`: 64-символьная шестнадцатеричная строка (32 байта) для AES-256-GCM шифрования. Можно сгенерировать командой: `openssl rand -hex 32`.
    *   `DATABASE_PATH`: (Опционально) Путь к файлу базы данных SQLite. По умолчанию `./secrets.db`.

2.  **Запустите проект**:
    ```bash
    docker-compose up --build -d
    ```

### Ручной запуск (для разработки)

1.  **Клонируйте репозиторий**:
    ```bash
    git clone https://github.com/your-username/vault_n8n.git
    cd vault_n8n
    ```

2.  **Создайте и активируйте виртуальное окружение**:
    ```bash
    python3.11 -m venv venv
    source venv/bin/activate
    ```

3.  **Установите зависимости**:
    ```bash
    pip install -r requirements.txt
    ```

4.  **Создайте `.env` файл**: (Как описано выше для Docker Compose).

5.  **Запустите приложение**:
    ```bash
    uvicorn app.main:app --host 0.0.0.0 --port 8000
    ```

## Конфигурация

Конфигурация приложения загружается из переменных окружения (включая `.env` файл).

**Обязательные переменные:**

-   `AUTH_TOKEN`: Токен для авторизации доступа к API.
-   `ENCRYPTION_KEY`: 64-символьная hex-строка (32 байта) для AES-256-GCM шифрования.

**Необязательные переменные:**

-   `DATABASE_PATH`: Путь к файлу базы данных SQLite. По умолчанию `./secrets.db`.

## Использование API

Все эндпоинты имеют префикс `/api/v1`. Формат данных - JSON.

### Авторизация

Для всех эндпоинтов требуется авторизация через заголовок `Authorization: Bearer <AUTH_TOKEN>`. `<AUTH_TOKEN>` должен соответствовать значению, указанному в переменной окружения `AUTH_TOKEN`.

### Примеры Curl

Предполагается, что `AUTH_TOKEN` равен `your_secret_token` и приложение запущено на `http://localhost:8000`.

#### Добавление/Обновление одного секрета

```bash
curl -X POST "http://localhost:8000/api/v1/secrets/single" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer your_secret_token" \
     -d '{ "key": "my_service_password", "value": "super_secret_password_123" }'
```

**Ожидаемый ответ (JSON):**

```json
[
  {
    "key": "my_service_password",
    "value": "super_secret_password_123"
  }
]
```

#### Массовое добавление/обновление секретов

```bash
curl -X POST "http://localhost:8000/api/v1/secrets/bulk" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer your_secret_token" \
     -d '[ { "key": "api_key_prod", "value": "prod_api_token_xyz" }, { "key": "db_user", "value": "admin_user" } ]'
```

**Ожидаемый ответ (JSON):**

```json
[
  {
    "key": "api_key_prod",
    "value": "prod_api_token_xyz"
  },
  {
    "key": "db_user",
    "value": "admin_user"
  }
]
```

#### Получение секретов

```bash
curl -X GET "http://localhost:8000/api/v1/secrets?keys=my_service_password,api_key_prod" \
     -H "Authorization: Bearer your_secret_token"
```

**Ожидаемый ответ (JSON):**

```json
[
  {
    "key": "my_service_password",
    "value": "super_secret_password_123"
  },
  {
    "key": "api_key_prod",
    "value": "prod_api_token_xyz"
  }
]
```

#### Удаление секретов

```bash
curl -X DELETE "http://localhost:8000/api/v1/secrets?keys=my_service_password,api_key_prod" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer your_secret_token"
```

**Ожидаемый ответ (JSON):**

```json
[
  {
    "key": "my_service_password",
    "value": "super_secret_password_123"
  },
  {
    "key": "api_key_prod",
    "value": "prod_api_token_xyz"
  }
]
```

## Интеграция с n8n

Для работы с VaultN8N через n8n используйте узел `HTTP Request`.

**Авторизация:**

В узле `HTTP Request` выберите:
- `Authentication`: `Predefined Credential Type`
- `Credential Type`: `HTTP Header Auth`
- `Name`: `Authorization`
- `Value`: `={{ $env.VAULT_N8N_AUTH_TOKEN }}` (замените `VAULT_N8N_AUTH_TOKEN` на имя вашей переменной окружения n8n, содержащей `AUTH_TOKEN` VaultN8N).

**Примеры использования:**

### Получение секретов (GET метод)

1.  **Метод:** `GET`
2.  **URL:** В поле "URL" укажите только базовый адрес без параметров:
    `http://vault_n8n:8000/api/v1/secrets` (если n8n и VaultN8N в одной Docker-сети) или полный внешний адрес.
3.  **Параметры запроса (Query Parameters):**
    *   Прокрутите вниз до раздела "Query Parameters".
    *   Добавьте новую строку параметров:
        *   `Name` (Имя): `keys`
        *   `Value` (Значение): `my_service_password,api_key_prod` (или используйте выражения, например `={{ $json.some_key }},{{ $json.another_key }}`)

### Добавление/Обновление секретов (POST метод)

1.  **Метод:** `POST`
2.  **URL:** В поле "URL" укажите:
    *   Для одного секрета: `http://vault_n8n:8000/api/v1/secrets/single`
    *   Для массового добавления: `http://vault_n8n:8000/api/v1/secrets/bulk`
3.  **Тело запроса (Body Parameters):**
    *   В разделе "Body Content" выберите `Body Content Type`: `JSON`.
    *   В текстовом поле JSON вставьте:
        *   Для одного секрета:
            ```json
            {
              "key": "my_new_secret",
              "value": "new_secret_value"
            }
            ```
        *   Для массового добавления (обратите внимание, что это прямой список):
            ```json
            [
              {
                "key": "batch_secret_1",
                "value": "batch_value_1"
              },
              {
                "key": "batch_secret_2",
                "value": "batch_value_2"
              }
            ]
            ```
            (Или используйте выражения для динамического формирования JSON)

## Тестирование

Для запуска тестов:

```bash
# Установите зависимости, если еще не сделали это
pip install -r requirements.txt
python -m pytest
```

## Советы по безопасности и эксплуатации

-   **HTTPS**: Всегда запускайте VaultN8N за обратным прокси (например, Nginx, Traefik), который обеспечивает HTTPS. Приложение не реализует HTTPS самостоятельно.
-   **Сетевая изоляция**: Ограничьте доступ к API VaultN8N только для доверенных сервисов (например, n8n) в вашей Docker-сети.
-   **Управление ключами**: `ENCRYPTION_KEY` и `AUTH_TOKEN` должны быть надежно защищены и не должны быть доступны публично. Используйте Docker Secrets или другие безопасные методы управления секретами.
-   **Резервное копирование БД**: Регулярно создавайте резервные копии файла базы данных (`secrets.db`), особенно если он хранится во внешнем томе.

## Публикация новой версии

Этот проект использует [GitHub Actions](https://github.com/features/actions) для автоматической сборки и публикации Docker-образа в [Docker Hub](https://hub.docker.com/).

Публикация новой версии происходит при создании и отправке в репозиторий нового Git-тега, соответствующего формату `v*.*.*` (например, `v1.0.0`, `v1.2.3`).

**Порядок действий для выпуска новой версии:**

1.  Убедитесь, что все последние изменения находятся в ветке `main`.

2.  Создайте новый тег, следуя принципам [семантического версионирования](https://semver.org/lang/ru/) (например, `v1.0.1` для исправления бага, `v1.1.0` для добавления новой функциональности).

    ```bash
    # Пример создания тега для версии 1.0.1
    git tag v1.0.1
    ```

3.  Отправьте тег в удаленный репозиторий.

    ```bash
    git push origin v1.0.1
    ```

4.  После этого GitHub Actions автоматически запустит процесс сборки и публикации. Вы можете отслеживать его выполнение во вкладке "Actions" вашего репозитория.