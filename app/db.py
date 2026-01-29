"""
Модуль для работы с базой данных SQLite.
Отвечает за инициализацию БД, создание таблиц и выполнение CRUD-операций.
"""
import sqlite3
import logging
from pathlib import Path
from typing import List, Tuple, Union, Optional

# Инициализация логгера
logger = logging.getLogger(__name__)

def _to_path(path: Union[str, Path]) -> Path:
    """Преобразует строку в Path, если необходимо."""
    return Path(path) if isinstance(path, str) else path

def init_db(db_path: Union[str, Path]) -> None:
    """
    Инициализирует базу данных и создает таблицы, если они не существуют.

    Создает:
    - таблицу `secrets` для хранения ключей и зашифрованных значений.
    - виртуальную таблицу `secrets_fts` для полнотекстового поиска по ключам.
    - триггеры для синхронизации `secrets` и `secrets_fts`.

    Аргументы:
        db_path (Union[str, Path]): Путь к файлу базы данных.
    """
    db_path = _to_path(db_path)
    try:
        # Создаем директорию для БД, если она не существует
        db_path.parent.mkdir(parents=True, exist_ok=True)
        
        with sqlite3.connect(db_path) as conn:
            cursor = conn.cursor()

            # Включаем поддержку внешних ключей для целостности данных
            cursor.execute("PRAGMA foreign_keys = ON;")

            # Основная таблица для хранения секретов
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS secrets (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    key TEXT UNIQUE NOT NULL COLLATE BINARY,
                    value TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
            """)

            # Индекс для ускорения поиска по ключу
            cursor.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_secrets_key ON secrets(key);")
            
            # Виртуальная таблица для полнотекстового поиска (FTS5)
            # content='secrets' указывает, что fts-таблица будет синхронизирована с `secrets`
            # content_rowid='id' связывает строки по id
            cursor.execute("""
                CREATE VIRTUAL TABLE IF NOT EXISTS secrets_fts USING fts5(
                    key,
                    content='secrets',
                    content_rowid='id'
                );
            """)

            # Триггеры для автоматической синхронизации fts-таблицы с основной
            # После вставки, обновления или удаления в `secrets`, `secrets_fts` обновляется
            cursor.executescript("""
                CREATE TRIGGER IF NOT EXISTS secrets_ai AFTER INSERT ON secrets BEGIN
                    INSERT INTO secrets_fts(rowid, key) VALUES (new.id, new.key);
                END;
                CREATE TRIGGER IF NOT EXISTS secrets_ad AFTER DELETE ON secrets BEGIN
                    INSERT INTO secrets_fts(secrets_fts, rowid, key) VALUES ('delete', old.id, old.key);
                END;
                CREATE TRIGGER IF NOT EXISTS secrets_au AFTER UPDATE ON secrets BEGIN
                    INSERT INTO secrets_fts(secrets_fts, rowid, key) VALUES ('delete', old.id, old.key);
                    INSERT INTO secrets_fts(rowid, key) VALUES (new.id, new.key);
                END;
            """)

            # Триггер для обновления поля updated_at
            cursor.execute("""
                CREATE TRIGGER IF NOT EXISTS set_timestamp
                AFTER UPDATE ON secrets
                FOR EACH ROW
                BEGIN
                    UPDATE secrets SET updated_at = CURRENT_TIMESTAMP WHERE id = old.id;
                END;
            """)

            conn.commit()
            logger.info(f"База данных успешно инициализирована по пути: {db_path}")

    except sqlite3.Error as e:
        logger.error(f"Ошибка при инициализации базы данных: {e}")
        raise

def add_or_update_secret(db_path: Union[str, Path], key: str, value: str) -> None:
    """
    Добавляет новый секрет или обновляет существующий.
    Использует `INSERT OR REPLACE` для атомарной операции.
    """
    db_path = _to_path(db_path)
    try:
        with sqlite3.connect(db_path) as conn:
            cursor = conn.cursor()
            cursor.execute(
                "INSERT INTO secrets (key, value) VALUES (?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = CURRENT_TIMESTAMP;",
                (key, value)
            )
            conn.commit()
            logger.info(f"Секрет с ключом '{key}' был успешно добавлен/обновлен.")
    except sqlite3.Error as e:
        logger.error(f"Ошибка при добавлении/обновлении секрета с ключом '{key}': {e}")
        raise

def get_secrets_by_keys(db_path: Union[str, Path], keys: List[str]) -> List[Tuple[str, str]]:
    """
    Извлекает секреты по списку точных ключей.
    """
    db_path = _to_path(db_path)
    try:
        with sqlite3.connect(db_path) as conn:
            cursor = conn.cursor()
            # Создаем плейсхолдеры для запроса IN
            placeholders = ','.join('?' for _ in keys)
            if not placeholders:
                return []
            query = f"SELECT key, value FROM secrets WHERE key IN ({placeholders});"
            cursor.execute(query, keys)
            return cursor.fetchall()
    except sqlite3.Error as e:
        logger.error(f"Ошибка при получении секретов по ключам: {e}")
        raise

def find_secrets_by_like_pattern(db_path: Union[str, Path], pattern: str) -> List[Tuple[str, str]]:
    """
    Ищет секреты, ключ которых соответствует шаблону (используя LIKE).
    Звездочка (*) в шаблоне заменяется на знак процента (%) для SQL LIKE.
    """
    db_path = _to_path(db_path)
    try:
        with sqlite3.connect(db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("PRAGMA case_sensitive_like = ON;") # Включаем чувствительность к регистру для LIKE
            # Заменяем * на % для LIKE
            like_pattern = pattern.replace('*', '%')
            query = "SELECT key, value FROM secrets WHERE key LIKE ?;"
            cursor.execute(query, (like_pattern,))
            return cursor.fetchall()
    except sqlite3.Error as e:
        logger.error(f"Ошибка при поиске секретов по шаблону '{pattern}': {e}")
        raise
        
def delete_secrets_by_keys(db_path: Union[str, Path], keys: List[str]) -> int:
    """
    Удаляет секреты по списку точных ключей.
    Возвращает количество удаленных строк.
    """
    db_path = _to_path(db_path)
    try:
        with sqlite3.connect(db_path) as conn:
            cursor = conn.cursor()
            placeholders = ','.join('?' for _ in keys)
            if not placeholders:
                return 0
            query = f"DELETE FROM secrets WHERE key IN ({placeholders});"
            cursor.execute(query, keys)
            deleted_count = cursor.rowcount
            conn.commit()
            logger.info(f"Удалено {deleted_count} секретов.")
            return deleted_count
    except sqlite3.Error as e:
        logger.error(f"Ошибка при удалении секретов по ключам: {e}")
        raise

def get_first_secret_value(db_path: Union[str, Path]) -> Optional[str]:
    """
    Извлекает значение первого секрета из базы данных.
    Используется для проверки ключа шифрования при старте.
    """
    db_path = _to_path(db_path)
    try:
        with sqlite3.connect(db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT value FROM secrets LIMIT 1;")
            result = cursor.fetchone()
            if result:
                return result[0]
            return None
    except sqlite3.Error as e:
        # Если таблицы еще нет, это не ошибка на данном этапе
        if "no such table" in str(e):
            logger.info("Таблица 'secrets' еще не создана, проверка ключа не требуется.")
            return None
        logger.error(f"Ошибка при получении первого секрета из БД: {e}")
        raise