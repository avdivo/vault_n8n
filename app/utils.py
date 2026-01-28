"""
Модуль для вспомогательных функций и настройки логирования.
"""
import logging
from pathlib import Path

def setup_logging(log_file: Path = Path("app.log")) -> None:
    """
    Настраивает логирование для приложения.
    Логи выводятся в консоль и записываются в файл app.log.
    """
    # Создаем корневой логгер
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)  # Устанавливаем уровень логирования по умолчанию

    # Форматтер для логов
    formatter = logging.Formatter(
        "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )

    # Консольный хендлер
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)

    # Файловый хендлер
    file_handler = logging.FileHandler(log_file)
    file_handler.setLevel(logging.INFO)
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    logger.info("Логирование настроено.")

# Пример использования:
# from app.utils import setup_logging
# setup_logging()
# logging.info("Это информационное сообщение.")
# logging.error("Это сообщение об ошибке.")
