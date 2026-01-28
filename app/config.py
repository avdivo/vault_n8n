"""
Модуль для загрузки и валидации конфигурации проекта.
Использует Pydantic для чтения переменных окружения из файла .env.
"""
from typing import ClassVar, Optional
from functools import lru_cache
from pathlib import Path

from pydantic import Field, field_validator, ValidationError
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """
    Класс для хранения и валидации настроек приложения.
    Загружает переменные из .env файла.

    Атрибуты:
        AUTH_TOKEN (str): Токен для авторизации доступа к API.
        ENCRYPTION_KEY (str): Ключ для шифрования данных (64-символьная hex-строка).
        DATABASE_PATH (str): Путь к файлу базы данных SQLite.
    """
    model_config: ClassVar[SettingsConfigDict] = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    AUTH_TOKEN: str = Field(..., description="Токен для авторизации доступа к API")
    ENCRYPTION_KEY: str = Field(..., description="Ключ шифрования (64-символьная hex-строка)")
    DATABASE_PATH: str = Field("./secrets.db", description="Путь к файлу базы данных SQLite")

    @field_validator("ENCRYPTION_KEY")
    def validate_encryption_key(cls, value: str) -> str:
        """
        Валидирует ключ шифрования.
        Ключ должен быть строкой, содержащей 32 байта в кодировке hex (64 символа).

        Аргументы:
            value (str): Значение ключа шифрования.

        Исключения:
            ValueError: Если ключ имеет некорректную длину или формат.

        Возвращает:
            str: Валидное значение ключа.
        """
        if len(value) != 64:
            raise ValueError("Длина ключа шифрования должна составлять 64 hex-символа")

        try:
            bytes.fromhex(value)
        except ValueError:
            raise ValueError("Ключ шифрования должен быть в формате hex") from None

        return value

@lru_cache()
def get_settings() -> Settings:
    """
    Фабричная функция для создания и получения экземпляра настроек.
    Использует кэширование, чтобы избежать многократного чтения .env файла.
    Выбрасывает исключение `ValidationError` с подробным сообщением при ошибке.

    Возвращает:
        Settings: Экземпляр настроек.

    Исключения:
        ValidationError: При ошибке валидации переменных окружения.
    """
    try:
        return Settings()

    except ValidationError as e:
        # Формируем более читабельное сообщение об ошибке
        error_messages = []
        for error in e.errors():
            field = ".".join(map(str, error["loc"]))
            message = error["msg"]
            error_messages.append(f"  - Переменная '{field}': {message}")

        raise ValueError(
            "Ошибка валидации конфигурации:\n" + "\n".join(error_messages)
        ) from e