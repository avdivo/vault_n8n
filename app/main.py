"""
Основной файл приложения FastAPI.
Отвечает за создание экземпляра FastAPI, подключение роутов и общую конфигурацию.
"""
from fastapi import FastAPI
from contextlib import asynccontextmanager
import logging

from app.api import routes as api_routes
from app.config import get_settings, Settings
from app.db import init_db
from app.utils import setup_logging

# Настраиваем логирование на старте модуля
setup_logging()

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Контекстный менеджер для управления жизненным циклом приложения.
    Выполняет код до запуска приложения (before startup) и после его остановки (after shutdown).
    """
    logging.info("Приложение запускается...")
    try:
        # Используем app.state для передачи настроек в тестах
        if hasattr(app.state, "settings"):
            settings = app.state.settings
        else:
            settings = get_settings()
        
        init_db(settings.DATABASE_PATH)
        app.state.settings = settings
    except Exception as e:
        logging.critical(f"Критическая ошибка при инициализации: {e}")
        raise
    yield
    logging.info("Приложение останавливается.")

# Создаем экземпляр FastAPI с использованием lifespan
app = FastAPI(
    title="VaultN8N",
    description="Минималистичное серверное приложение для хранения и выдачи секретов.",
    version="1.0.0",
    lifespan=lifespan
)

# Подключаем роуты API
app.include_router(api_routes.router)

@app.get("/", tags=["Root"])
def read_root():
    """
    Корневой эндпоинт для проверки работоспособности.
    """
    return {"message": "Welcome to VaultN8N"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
