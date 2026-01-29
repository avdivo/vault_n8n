"""
Модуль для выполнения проверок при запуске приложения.
"""
import logging
import sys

from app.config import Settings
from app.db import get_first_secret_value
from app.crypto import decrypt_data, DecryptionError

logger = logging.getLogger(__name__)

def check_encryption_key(settings: Settings):
    """
    Проверяет корректность ключа шифрования путем попытки дешифровать
    первую попавшуюся запись в базе данных.

    Если база данных пуста, проверка успешно проходит.
    Если дешифрование не удается, выводит критическую ошибку и завершает работу.
    """
    logger.info("Проверка ключа шифрования...")
    
    first_value = get_first_secret_value(settings.DATABASE_PATH)
    
    # Если база данных пуста, проверять нечего.
    if first_value is None:
        logger.info("База данных пуста. Проверка ключа не требуется.")
        return

    # Пытаемся дешифровать первое значение
    try:
        decrypt_data(first_value, settings.ENCRYPTION_KEY)
        logger.info("Ключ шифрования успешно проверен.")
    except DecryptionError as e:
        logger.critical("=" * 80)
        logger.critical("!!! КРИТИЧЕСКАЯ ОШИБКА ПРИ ЗАПУСКЕ !!!")
        logger.critical("Не удалось расшифровать данные из базы данных.")
        logger.critical(f"Ошибка: {e}")
        logger.critical("Вероятная причина: используется неверный ENCRYPTION_KEY.")
        logger.critical("Убедитесь, что в .env файле указан тот же ключ, которым были зашифрованы данные.")
        logger.critical("Приложение будет остановлено.")
        logger.critical("=" * 80)
        # Завершаем работу приложения с кодом ошибки
        sys.exit(1)
