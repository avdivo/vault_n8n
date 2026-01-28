"""
Модуль для аутентификации и авторизации.
Содержит зависимость FastAPI для проверки токена доступа.
"""
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import secrets
from app.config import get_settings, Settings

# Схема HTTPBearer для получения токена из заголовка Authorization: Bearer <token>
security_scheme = HTTPBearer(scheme_name="Bearer")

def verify_token(
    credentials: HTTPAuthorizationCredentials = Depends(security_scheme), 
    settings: Settings = Depends(get_settings)
) -> None:
    """
    Зависимость FastAPI для проверки токена доступа.

    Сравнивает токен из запроса с токеном из настроек.
    Использует `secrets.compare_digest` для защиты от атак по времени.

    Аргументы:
        credentials (HTTPAuthorizationCredentials): Учетные данные авторизации, извлеченные из заголовка.
        settings (Settings): Экземпляр настроек приложения.

    Исключения:
        HTTPException(401): Если токен невалиден или отсутствует.
    """
    if not secrets.compare_digest(credentials.credentials, settings.AUTH_TOKEN):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Неверный токен аутентификации",
            headers={"WWW-Authenticate": "Bearer"},
        )
