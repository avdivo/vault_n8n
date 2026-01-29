"""
Тесты для модуля шифрования `app.crypto`.
"""
import pytest
from app.crypto import encrypt_data, decrypt_data, DecryptionError
from cryptography.exceptions import InvalidTag
import os

# Фиктивный ключ шифрования для тестов (64 hex-символа = 32 байта)
TEST_ENCRYPTION_KEY = os.urandom(32).hex()

def test_encrypt_decrypt_success() -> None:
    """
    Проверяет успешное шифрование и последующее дешифрование данных.
    """
    original_data = "Hello, world! This is a test message with some special characters: !@#$%^&*()_+"
    encrypted_data = encrypt_data(original_data, TEST_ENCRYPTION_KEY)
    decrypted_data = decrypt_data(encrypted_data, TEST_ENCRYPTION_KEY)

    assert decrypted_data == original_data
    assert encrypted_data != original_data  # Убедимся, что данные действительно зашифрованы

def test_decrypt_with_incorrect_key() -> None:
    """
    Проверяет, что дешифрование с неправильным ключом приводит к ошибке.
    """
    original_data = "Sensitive information"
    encrypted_data = encrypt_data(original_data, TEST_ENCRYPTION_KEY)

    # Генерируем другой ключ
    incorrect_key = os.urandom(32).hex()

    with pytest.raises(DecryptionError, match="Ошибка аутентификации данных"):
        decrypt_data(encrypted_data, incorrect_key)

def test_decrypt_with_corrupted_data() -> None:
    """
    Проверяет, что дешифрование поврежденных данных приводит к ошибке.
    """
    original_data = "Data to be corrupted"
    encrypted_data = encrypt_data(original_data, TEST_ENCRYPTION_KEY)

    # Повреждаем часть зашифрованных данных
    parts = encrypted_data.split('.')
    # Изменяем один символ в шифротексте, чтобы нарушить аутентификацию
    corrupted_ciphertext = parts[2][:-1] + ('A' if parts[2][-1] != 'A' else 'B')
    corrupted_encrypted_data = f"{parts[0]}.{parts[1]}.{corrupted_ciphertext}.{parts[3]}"


    with pytest.raises(DecryptionError, match="Ошибка аутентификации данных"):
        decrypt_data(corrupted_encrypted_data, TEST_ENCRYPTION_KEY)

def test_decrypt_with_invalid_format() -> None:
    """
    Проверяет, что дешифрование данных в некорректном формате приводит к ошибке.
    """
    invalid_format_data = "part1.part2.part3"  # Не хватает одной части
    with pytest.raises(DecryptionError, match="Некорректный формат зашифрованных данных"):
        decrypt_data(invalid_format_data, TEST_ENCRYPTION_KEY)

    invalid_base64_data = "invalid-base64-!.invalid-base64-!.invalid-base64-!.invalid-base64-!"
    with pytest.raises(DecryptionError, match="Ошибка декодирования base64 частей зашифрованных данных"):
        decrypt_data(invalid_base64_data, TEST_ENCRYPTION_KEY)
