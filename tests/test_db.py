"""
Тесты для модуля работы с базой данных `app.db`.
"""
import sqlite3
import pytest
from pathlib import Path
from app.db import (
    init_db, 
    add_or_update_secret, 
    get_secrets_by_keys, 
    find_secrets_by_like_pattern, 
    delete_secrets_by_keys
)

@pytest.fixture
def db_path(tmp_path: Path) -> Path:
    """
    Фикстура, предоставляющая путь к временному файлу базы данных.
    """
    db = tmp_path / "test_secrets.db"
    init_db(db)
    return db


def test_init_db_creates_database_and_tables(db_path: Path) -> None:
    """
    Проверяет, что `init_db` корректно создает файл БД и все необходимые таблицы и триггеры.
    """
    # Файл и таблицы уже созданы фикстурой, поэтому просто проверяем их наличие
    assert db_path.exists() and db_path.is_file()

    with sqlite3.connect(db_path) as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='secrets';")
        assert cursor.fetchone() is not None
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='secrets_fts';")
        assert cursor.fetchone() is not None


def test_add_and_get_secret(db_path: Path) -> None:
    """
    Проверяет добавление и последующее получение секрета.
    """
    add_or_update_secret(db_path, "test_key", "test_value")
    
    secrets = get_secrets_by_keys(db_path, ["test_key"])
    assert len(secrets) == 1
    assert secrets[0] == ("test_key", "test_value")


def test_update_secret(db_path: Path) -> None:
    """
    Проверяет обновление существующего секрета.
    """
    add_or_update_secret(db_path, "key_to_update", "initial_value")
    
    # Обновляем значение
    add_or_update_secret(db_path, "key_to_update", "updated_value")
    
    secrets = get_secrets_by_keys(db_path, ["key_to_update"])
    assert len(secrets) == 1
    assert secrets[0] == ("key_to_update", "updated_value")


def test_get_multiple_secrets(db_path: Path) -> None:
    """
    Проверяет получение нескольких секретов одним запросом.
    """
    add_or_update_secret(db_path, "key1", "value1")
    add_or_update_secret(db_path, "key2", "value2")
    add_or_update_secret(db_path, "key3", "value3")
    
    secrets = get_secrets_by_keys(db_path, ["key1", "key3", "non_existent_key"])
    assert len(secrets) == 2
    # Преобразуем в set для проверки независимо от порядка
    assert set(secrets) == {("key1", "value1"), ("key3", "value3")}


def test_find_secrets_by_like_pattern(db_path: Path) -> None:
    """
    Проверяет поиск секретов по шаблону с использованием LIKE.
    """
    add_or_update_secret(db_path, "service-A-token", "tokenA")
    add_or_update_secret(db_path, "service-B-token", "tokenB")
    add_or_update_secret(db_path, "common-key", "commonValue")
    
    # Ищем все ключи, начинающиеся с "service-"
    found = find_secrets_by_like_pattern(db_path, "service-*")
    assert len(found) == 2
    assert set(found) == {("service-A-token", "tokenA"), ("service-B-token", "tokenB")}
    
    # Ищем конкретный ключ
    found = find_secrets_by_like_pattern(db_path, "common-key")
    assert len(found) == 1
    assert found[0] == ("common-key", "commonValue")


def test_delete_secrets(db_path: Path) -> None:
    """
    Проверяет удаление секретов.
    """
    add_or_update_secret(db_path, "key_to_delete1", "value1")
    add_or_update_secret(db_path, "key_to_keep", "value2")
    add_or_update_secret(db_path, "key_to_delete2", "value3")
    
    # Удаляем два ключа
    deleted_count = delete_secrets_by_keys(db_path, ["key_to_delete1", "key_to_delete2"])
    assert deleted_count == 2
    
    # Проверяем, что остались только нужные ключи
    all_secrets = get_secrets_by_keys(db_path, ["key_to_delete1", "key_to_keep", "key_to_delete2"])
    assert len(all_secrets) == 1
    assert all_secrets[0] == ("key_to_keep", "value2")

    # Проверяем FTS-таблицу
    with sqlite3.connect(db_path) as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM secrets_fts WHERE key MATCH 'key_to_delete*';")
        assert cursor.fetchone() is None, "Записи в FTS таблице не были удалены"

def test_case_sensitive_keys(db_path: Path) -> None:
    """
    Проверяет чувствительность ключей к регистру.
    """
    # Добавляем секрет
    add_or_update_secret(db_path, "MySecretKey", "my_value_1")

    # Попытка получить по другому регистру - должен вернуть пустой список
    secrets_lower = get_secrets_by_keys(db_path, ["mysecretkey"])
    assert len(secrets_lower) == 0

    # Получаем по правильному регистру - должен найти
    secrets_correct = get_secrets_by_keys(db_path, ["MySecretKey"])
    assert len(secrets_correct) == 1
    assert secrets_correct[0] == ("MySecretKey", "my_value_1")

    # Добавляем другой секрет с тем же именем, но другим регистром
    add_or_update_secret(db_path, "mysecretkey", "my_value_2")

    # Теперь должны быть оба секрета
    all_secrets = get_secrets_by_keys(db_path, ["MySecretKey", "mysecretkey"])
    assert len(all_secrets) == 2
    assert set(all_secrets) == {("MySecretKey", "my_value_1"), ("mysecretkey", "my_value_2")}

    # Проверяем обновление: должно обновить "MySecretKey"
    add_or_update_secret(db_path, "MySecretKey", "updated_value_1")
    secrets = get_secrets_by_keys(db_path, ["MySecretKey"])
    assert secrets[0] == ("MySecretKey", "updated_value_1")

    # Проверяем, что "mysecretkey" не изменился
    secrets = get_secrets_by_keys(db_path, ["mysecretkey"])
    assert secrets[0] == ("mysecretkey", "my_value_2")

    # Тестируем поиск по LIKE с учетом регистра
    add_or_update_secret(db_path, "FooBar", "foo_bar_val")
    add_or_update_secret(db_path, "foobar", "FOO_BAR_VAL")

    found_upper = find_secrets_by_like_pattern(db_path, "Foo*")
    assert len(found_upper) == 1
    assert found_upper[0][0] == "FooBar"

    found_lower = find_secrets_by_like_pattern(db_path, "foo*")
    assert len(found_lower) == 1
    assert found_lower[0][0] == "foobar"

    # Тестируем удаление с учетом регистра
    delete_secrets_by_keys(db_path, ["MySecretKey"])
    remaining = get_secrets_by_keys(db_path, ["MySecretKey", "mysecretkey"])
    assert len(remaining) == 1
    assert remaining[0][0] == "mysecretkey"
