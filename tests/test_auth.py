"""
Тесты для модуля аутентификации `app.auth`.
"""
import pytest
from fastapi import FastAPI, Depends, HTTPException
from fastapi.testclient import TestClient
from app.auth import verify_token
from app.config import Settings, get_settings

# Фиктивный токен для тестов
TEST_AUTH_TOKEN = "test-secret-token"

# Переопределяем зависимость get_settings для тестов
def override_get_settings() -> Settings:
    """
    Возвращает тестовые настройки с фиксированным токеном.
    """
    return Settings(AUTH_TOKEN=TEST_AUTH_TOKEN, ENCRYPTION_KEY="0"*64)

# Создаем тестовое приложение FastAPI
app = FastAPI()

@app.get("/secure-endpoint", dependencies=[Depends(verify_token)])
def secure_endpoint():
    """
    Защищенный эндпоинт для тестирования зависимости.
    """
    return {"status": "ok"}

# Применяем переопределение зависимости
app.dependency_overrides[get_settings] = override_get_settings

# Создаем тестовый клиент
client = TestClient(app)


def test_verify_token_success() -> None:
    """
    Проверяет успешный доступ к эндпоинту с корректным токеном.
    """
    response = client.get(
        "/secure-endpoint",
        headers={"Authorization": f"Bearer {TEST_AUTH_TOKEN}"}
    )
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_verify_token_invalid_token() -> None:
    """
    Проверяет, что доступ запрещен при использовании неверного токена.
    """
    response = client.get(
        "/secure-endpoint",
        headers={"Authorization": "Bearer invalid-token"}
    )
    assert response.status_code == 401
    assert "Неверный токен аутентификации" in response.json()["detail"]


def test_verify_token_missing_header() -> None:
    """
    Проверяет, что доступ запрещен при отсутствии заголовка Authorization.
    """
    response = client.get("/secure-endpoint")
    assert response.status_code == 401 # FastAPI TestClient автоматически обрабатывает это
    assert "Not authenticated" in response.json()["detail"]


def test_verify_token_malformed_header() -> None:
    """
    Проверяет, что доступ запрещен при некорректно сформированном заголовке.
    """
    response = client.get(
        "/secure-endpoint",
        headers={"Authorization": "Token missing-bearer"}
    )
    assert response.status_code == 401
    assert "Not authenticated" in response.json()["detail"]
