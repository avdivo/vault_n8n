"""
Модуль с эндпоинтами API.
"""
from fastapi import APIRouter, Depends, HTTPException, status, Body, Query
from typing import List

from app import models, crypto, db, auth
from app.config import get_settings, Settings

router = APIRouter(
    prefix="/api/v1",
    tags=["secrets"],
    dependencies=[Depends(auth.verify_token)],
)

@router.post("/secrets/single", response_model=List[models.Secret])
def create_or_update_secret(
    secret: models.SecretCreate,
    settings: Settings = Depends(get_settings)
):
    """
    Создает новый секрет или обновляет существующий.
    """
    try:
        # Шифруем значение перед сохранением
        encrypted_value = crypto.encrypt_data(secret.value, settings.ENCRYPTION_KEY)
        
        # Сохраняем в БД
        db.add_or_update_secret(settings.DATABASE_PATH, secret.key, encrypted_value)
        
        # Возвращаем расшифрованный секрет в виде списка
        return [models.Secret(key=secret.key, value=secret.value)]
        
    except Exception as e:
        # Логирование ошибки должно быть добавлено
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Внутренняя ошибка сервера: {e}",
        )

@router.post("/secrets/bulk", response_model=List[models.Secret])
def create_or_update_secrets_bulk(
    bulk_data: List[models.SecretCreate],
    settings: Settings = Depends(get_settings)
):
    """
    Массово создает или обновляет секреты.
    """
    try:
        processed_secrets = []
        for secret in bulk_data:
            encrypted_value = crypto.encrypt_data(secret.value, settings.ENCRYPTION_KEY)
            db.add_or_update_secret(settings.DATABASE_PATH, secret.key, encrypted_value)
            processed_secrets.append(models.Secret(key=secret.key, value=secret.value))
            
        return processed_secrets
        
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Внутренняя ошибка сервера: {e}",
        )

@router.get("/secrets", response_model=List[models.Secret])
def get_secrets(
    keys: str = Query(..., description="Список ключей или шаблонов через запятую"),
    settings: Settings = Depends(get_settings)
):
    """
    Извлекает секреты по списку ключей и/или шаблонам.
    """
    try:
        key_list = [k.strip() for k in keys.split(',')]
        
        found_secrets = []
        exact_keys = [k for k in key_list if '*' not in k]
        like_patterns = [k for k in key_list if '*' in k]

        if exact_keys:
            secrets_from_db = db.get_secrets_by_keys(settings.DATABASE_PATH, exact_keys)
            found_secrets.extend(secrets_from_db)

        for pattern in like_patterns:
            secrets_from_db = db.find_secrets_by_like_pattern(settings.DATABASE_PATH, pattern)
            found_secrets.extend(secrets_from_db)
            
        # Дешифруем значения
        decrypted_secrets = [
            models.Secret(key=k, value=crypto.decrypt_data(v, settings.ENCRYPTION_KEY))
            for k, v in found_secrets
        ]
        
        return decrypted_secrets

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Внутренняя ошибка сервера: {e}",
        )

@router.delete("/secrets", response_model=List[models.Secret])
def delete_secrets(
    keys: str = Query(..., description="Список ключей или шаблонов для удаления"),
    settings: Settings = Depends(get_settings)
):
    """
    Удаляет секреты по списку ключей и/или шаблонам.
    """
    try:
        key_list = [k.strip() for k in keys.split(',')]
        
        # Сначала находим все секреты, которые нужно удалить
        found_secrets = []
        exact_keys = [k for k in key_list if '*' not in k]
        like_patterns = [k for k in key_list if '*' in k]

        if exact_keys:
            secrets_from_db = db.get_secrets_by_keys(settings.DATABASE_PATH, exact_keys)
            found_secrets.extend(secrets_from_db)

        for pattern in like_patterns:
            secrets_from_db = db.find_secrets_by_like_pattern(settings.DATABASE_PATH, pattern)
            # Избегаем дубликатов
            for s in secrets_from_db:
                if s not in found_secrets:
                    found_secrets.append(s)
        
        if not found_secrets:
            return []

        # Удаляем ключи
        keys_to_delete = [k for k, v in found_secrets]
        db.delete_secrets_by_keys(settings.DATABASE_PATH, keys_to_delete)

        # Дешифруем значения для ответа
        decrypted_secrets = [
            models.Secret(key=k, value=crypto.decrypt_data(v, settings.ENCRYPTION_KEY))
            for k, v in found_secrets
        ]
        
        return decrypted_secrets

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Внутренняя ошибка сервера: {e}",
        )
