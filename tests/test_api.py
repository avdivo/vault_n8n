"""
Тесты для API эндпоинтов.
"""
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.config import Settings, get_settings
from app.db import get_secrets_by_keys, add_or_update_secret
from app.crypto import decrypt_data, encrypt_data
from pathlib import Path

# Фиктивный токен для тестов
TEST_AUTH_TOKEN = "test-api-secret-token"
TEST_ENCRYPTION_KEY = "a" * 64  # 32-байтный ключ в hex

@pytest.fixture
def test_db_path(tmp_path: Path) -> Path:
    """
    Фикстура для создания временной БД для тестов API.
    """
    return tmp_path / "test_api.db"

@pytest.fixture
def client(test_db_path: Path) -> TestClient:
    """
    Фикстура, которая создает и настраивает тестовый клиент.
    """
    # Создаем тестовые настройки
    test_settings = Settings(
        AUTH_TOKEN=TEST_AUTH_TOKEN,
        ENCRYPTION_KEY=TEST_ENCRYPTION_KEY,
        DATABASE_PATH=str(test_db_path),
    )
    # Устанавливаем настройки в app.state до запуска клиента
    app.state.settings = test_settings
    
    # Переопределяем зависимость, чтобы эндпоинты тоже использовали тестовые настройки
    app.dependency_overrides[get_settings] = lambda: test_settings

    with TestClient(app) as test_client:
        yield test_client

    # Очищаем
    app.dependency_overrides = {}
    del app.state.settings


def test_create_secret_single(client: TestClient, test_db_path: Path) -> None:
    """
    Тестирует эндпоинт POST /api/v1/secrets/single.
    """
    secret_key = "my_secret_key"
    secret_value = "my_secret_value"

    response = client.post(
        "/api/v1/secrets/single",
        headers={"Authorization": f"Bearer {TEST_AUTH_TOKEN}"},
        json={"key": secret_key, "value": secret_value},
    )

    # 1. Проверяем успешный ответ
    assert response.status_code == 200
    response_data = response.json()
    assert isinstance(response_data, list)
    assert len(response_data) == 1
    assert response_data[0]["key"] == secret_key
    assert response_data[0]["value"] == secret_value

    # 2. Проверяем, что данные в БД зашифрованы
    secrets_from_db = get_secrets_by_keys(test_db_path, [secret_key])
    assert len(secrets_from_db) == 1

    encrypted_value_from_db = secrets_from_db[0][1]
    assert encrypted_value_from_db != secret_value

    # 3. Проверяем, что можем расшифровать данные из БД
    decrypted_value = decrypt_data(encrypted_value_from_db, TEST_ENCRYPTION_KEY)
    assert decrypted_value == secret_value


def test_create_secret_unauthorized(client: TestClient) -> None:
    """
    Тестирует эндпоинт POST /api/v1/secrets/single без авторизации.
    """
    response = client.post(
        "/api/v1/secrets/single",
        json={"key": "any_key", "value": "any_value"},
    )
    assert response.status_code == 401

def test_create_secrets_bulk(client: TestClient, test_db_path: Path) -> None:
    """
    Тестирует эндпоинт POST /api/v1/secrets/bulk.
    """
    secrets_to_create = [
        {"key": "bulk_key1", "value": "bulk_value1"},
        {"key": "bulk_key2", "value": "bulk_value2"},
    ]

    response = client.post(
        "/api/v1/secrets/bulk",
        headers={"Authorization": f"Bearer {TEST_AUTH_TOKEN}"},
        json=secrets_to_create,
    )

    # 1. Проверяем успешный ответ
    assert response.status_code == 200
    response_data = response.json()
    assert response_data == secrets_to_create

    # 2. Проверяем, что данные в БД зашифрованы
    keys = [s["key"] for s in secrets_to_create]
    secrets_from_db = get_secrets_by_keys(test_db_path, keys)
    assert len(secrets_from_db) == 2

    for key, encrypted_value in secrets_from_db:
        original_value = next(s["value"] for s in secrets_to_create if s["key"] == key)
        assert encrypted_value != original_value
        decrypted_value = decrypt_data(encrypted_value, TEST_ENCRYPTION_KEY)
        assert decrypted_value == original_value

def test_get_secrets(client: TestClient, test_db_path: Path) -> None:
    """
    Тестирует эндпоинт GET /api/v1/secrets.
    """
    # 1. Наполняем БД тестовыми данными
    secrets_data = {
        "service-A-token": "tokenA",
        "service-B-token": "tokenB",
        "common-key": "commonValue",
    }
    for key, value in secrets_data.items():
        encrypted_value = encrypt_data(value, TEST_ENCRYPTION_KEY) # Шифруем для записи в БД
        add_or_update_secret(test_db_path, key, encrypted_value)

    # 2. Тестируем получение по точному ключу
    response = client.get(
        "/api/v1/secrets?keys=common-key",
        headers={"Authorization": f"Bearer {TEST_AUTH_TOKEN}"},
    )
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0] == {"key": "common-key", "value": "commonValue"}

    # 3. Тестируем получение по шаблону
    response = client.get(
        "/api/v1/secrets?keys=service-*",
        headers={"Authorization": f"Bearer {TEST_AUTH_TOKEN}"},
    )
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 2
    assert set(tuple(s.items()) for s in data) == {
        (("key", "service-A-token"), ("value", "tokenA")),
        (("key", "service-B-token"), ("value", "tokenB")),
    }

    # 4. Тестируем комбинированный запрос
    response = client.get(
        "/api/v1/secrets?keys=service-A-token,common-key,non-existent",
        headers={"Authorization": f"Bearer {TEST_AUTH_TOKEN}"},
    )
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 2
    assert set(tuple(s.items()) for s in data) == {
        (("key", "service-A-token"), ("value", "tokenA")),
        (("key", "common-key"), ("value", "commonValue")),
    }

    # 5. Тестируем пустой результат
    response = client.get(
        "/api/v1/secrets?keys=non-existent",
        headers={"Authorization": f"Bearer {TEST_AUTH_TOKEN}"},
    )
    assert response.status_code == 200
    assert response.json() == []

def test_delete_secrets(client: TestClient, test_db_path: Path) -> None:
    """
    Тестирует эндпоинт DELETE /api/v1/secrets.
    """
    # 1. Наполняем БД тестовыми данными
    secrets_data = {
        "service-A-token": "tokenA",
        "service-B-token": "tokenB",
        "common-key": "commonValue",
        "to-delete": "value-to-delete",
    }
    for key, value in secrets_data.items():
        encrypted_value = encrypt_data(value, TEST_ENCRYPTION_KEY)
        add_or_update_secret(test_db_path, key, encrypted_value)

    # 2. Удаляем по точному ключу
    response = client.delete(
        "/api/v1/secrets?keys=to-delete",
        headers={"Authorization": f"Bearer {TEST_AUTH_TOKEN}"},
    )
    assert response.status_code == 200
    deleted_data = response.json()
    assert len(deleted_data) == 1
    assert deleted_data[0] == {"key": "to-delete", "value": "value-to-delete"}

    # Проверяем, что ключ удален из БД
    secrets_in_db = get_secrets_by_keys(test_db_path, ["to-delete"])
    assert len(secrets_in_db) == 0

    # 3. Удаляем по шаблону
    response = client.delete(
        "/api/v1/secrets?keys=service-*",
        headers={"Authorization": f"Bearer {TEST_AUTH_TOKEN}"},
    )
    assert response.status_code == 200
    deleted_data = response.json()
    assert len(deleted_data) == 2
    assert set(tuple(s.items()) for s in deleted_data) == {
        (("key", "service-A-token"), ("value", "tokenA")),
        (("key", "service-B-token"), ("value", "tokenB")),
    }
    
    # Проверяем, что остались только нужные ключи
    secrets_in_db = get_secrets_by_keys(test_db_path, ["service-A-token", "service-B-token", "common-key"])
    assert len(secrets_in_db) == 1
    assert secrets_in_db[0][0] == "common-key"
