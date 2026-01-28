
"""
Модуль с Pydantic-моделями для валидации данных API.
"""
from typing import List
from pydantic import BaseModel, Field

# Максимальная длина ключа и значения секрета
MAX_KEY_LENGTH = 100
MAX_VALUE_LENGTH = 100

class SecretBase(BaseModel):
    """
    Базовая модель секрета.
    """
    key: str = Field(
        ...,
        description="Ключ секрета",
        max_length=MAX_KEY_LENGTH,
    )
    value: str = Field(
        ...,
        description="Значение секрета",
        max_length=MAX_VALUE_LENGTH,
    )

class SecretCreate(SecretBase):
    """
    Модель для создания/обновления секрета.
    """
    pass

class Secret(SecretBase):
    """
    Модель для отображения секрета.
    """
    pass

