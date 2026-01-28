"""
Тесты для модуля конфигурации `app.config`.
"""
import os
import pytest
from pydantic import ValidationError
from typing import Generator

# Ключ для тестов: 32 байта в hex-представлении
VALID_ENCRYPTION_KEY_HEX = "0" * 64
INVALID_ENCRYPTION_KEY_SHORT = "1" * 63  # Неправильная длина
INVALID_ENCRYPTION_KEY_LONG = "2" * 65   # Неправильная длина
INVALID_ENCRYPTION_KEY_FORMAT = "g" * 64 # Неправильный формат (не hex)


@pytest.fixture(autouse=True)
def clear_env_vars() -> Generator[None, None, None]:
    """
    Фикстура для очистки переменных окружения, используемых в тестах,
    до и после каждого теста. Это обеспечивает изоляцию тестов.
    """
    env_keys = ["AUTH_TOKEN", "ENCRYPTION_KEY", "DATABASE_PATH"]
    original_values = {key: os.environ.get(key) for key in env_keys}

    # Очищаем переменные перед тестом
    for key in env_keys:
        if key in os.environ:
            del os.environ[key]

    # Очищаем кэш get_settings перед каждым тестом
    from app import config
    config.get_settings.cache_clear()

    yield

    # Восстанавливаем исходные значения после теста
    for key, value in original_values.items():
        if value is not None:
            os.environ[key] = value
        elif key in os.environ:
            del os.environ[key]
    
    # Очищаем кэш после теста на всякий случай
    config.get_settings.cache_clear()


def test_successful_config_loading(monkeypatch: pytest.MonkeyPatch) -> None:
    """
    Проверяет успешную загрузку конфигурации при корректно
    заданных переменных окружения.

    Аргументы:
        monkeypatch (pytest.MonkeyPatch): Фикстура для установки переменных окружения.
    """
    monkeypatch.setenv("AUTH_TOKEN", "test_token")
    monkeypatch.setenv("ENCRYPTION_KEY", VALID_ENCRYPTION_KEY_HEX)
    monkeypatch.setenv("DATABASE_PATH", "/tmp/test.db")

    # Динамический импорт, чтобы перечитать переменные
    from app import config
    import importlib
    importlib.reload(config)

    settings = config.get_settings()

    assert settings.AUTH_TOKEN == "test_token"
    assert settings.ENCRYPTION_KEY == VALID_ENCRYPTION_KEY_HEX
    assert settings.DATABASE_PATH == "/tmp/test.db"


def test_missing_auth_token_raises_error(monkeypatch: pytest.MonkeyPatch) -> None:
    """
    Проверяет, что при отсутствии переменной AUTH_TOKEN выбрасывается исключение.

    Аргументы:
        monkeypatch (pytest.MonkeyPatch): Фикстура для установки переменных окружения.
    """
    monkeypatch.setenv("ENCRYPTION_KEY", VALID_ENCRYPTION_KEY_HEX)

    with pytest.raises(ValueError, match="Переменная 'AUTH_TOKEN'"):
        from app import config
        monkeypatch.setitem(config.Settings.model_config, 'env_file', None)
        config.get_settings()


def test_missing_encryption_key_raises_error(monkeypatch: pytest.MonkeyPatch) -> None:
    """
    Проверяет, что при отсутствии переменной ENCRYPTION_KEY выбрасывается исключение.

    Аргументы:
        monkeypatch (pytest.MonkeyPatch): Фикстура для установки переменных окружения.
    """
    monkeypatch.setenv("AUTH_TOKEN", "test_token")

    with pytest.raises(ValueError, match="Переменная 'ENCRYPTION_KEY'"):
        from app import config
        monkeypatch.setitem(config.Settings.model_config, 'env_file', None)
        config.get_settings()


@pytest.mark.parametrize(
    "key, error_message",
    [
        (INVALID_ENCRYPTION_KEY_SHORT, "Длина ключа шифрования должна составлять 64 hex-символа"),
        (INVALID_ENCRYPTION_KEY_LONG, "Длина ключа шифрования должна составлять 64 hex-символа"),
        (INVALID_ENCRYPTION_KEY_FORMAT, "Ключ шифрования должен быть в формате hex"),
    ],
)
def test_invalid_encryption_key_raises_error(
    monkeypatch: pytest.MonkeyPatch, key: str, error_message: str
) -> None:
    """
    Проверяет, что при некорректном формате или длине ENCRYPTION_KEY
    выбрасывается исключение с соответствующим сообщением.

    Аргументы:
        monkeypatch (pytest.MonkeyPatch): Фикстура для установки переменных окружения.
        key (str): Некорректный ключ для теста.
        error_message (str): Ожидаемое сообщение об ошибке.
    """
    monkeypatch.setenv("AUTH_TOKEN", "test_token")
    monkeypatch.setenv("ENCRYPTION_KEY", key)

    with pytest.raises(ValueError, match=error_message):
        from app import config
        monkeypatch.setitem(config.Settings.model_config, 'env_file', None)
        config.get_settings()

def test_default_database_path(monkeypatch: pytest.MonkeyPatch) -> None:
    """
    Проверяет, что используется путь к базе данных по умолчанию,
    если он не указан в переменных окружения.

    Args:
        monkeypatch (pytest.MonkeyPatch): Фикстура для установки переменных окружения.
    """
    monkeypatch.setenv("AUTH_TOKEN", "test_token")
    monkeypatch.setenv("ENCRYPTION_KEY", VALID_ENCRYPTION_KEY_HEX)

    from app import config
    import importlib
    importlib.reload(config)

    settings = config.get_settings()

    assert settings.DATABASE_PATH == "./secrets.db"