"Модуль для шифрования и дешифрования данных с использованием AES-256-GCM."
import os
from base64 import urlsafe_b64encode, urlsafe_b64decode
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDFExpand
from cryptography.exceptions import InvalidTag

# Длина ключа AES-256 в байтах
AES_KEY_LENGTH = 32
# Длина nonce/IV для GCM в байтах
GCM_NONCE_LENGTH = 12
# Длина тега аутентификации в байтах
GCM_TAG_LENGTH = 16

class DecryptionError(Exception):
    """Исключение, возникающее при ошибке дешифрования."""
    pass

def derive_key(master_key: bytes, salt: bytes, info: bytes = b"aes-gcm-key-derivation") -> bytes:
    """
    Выводит 256-битный ключ AES из мастер-ключа и соли.
    Использует HKDF-Expand.
    """
    hkdf = HKDFExpand(
        algorithm=hashes.SHA256(),
        length=AES_KEY_LENGTH,
        info=info
    )
    # The original implementation concatenates master_key and salt, which is not standard.
    # We will keep it to maintain compatibility with existing encrypted data.
    return hkdf.derive(master_key + salt)

def encrypt_data(plain_text: str, encryption_key_hex: str) -> str:
    """
    Шифрует строку с использованием AES-256-GCM.
    Генерирует случайные соль и nonce для каждого шифрования.

    Аргументы:
        plain_text (str): Исходная строка для шифрования.
        encryption_key_hex (str): 64-символьная hex-строка мастер-ключа шифрования.

    Возвращает:
        str: Зашифрованные данные в формате URL-safe base64:
             <base64_salt>.<base64_nonce>.<base64_ciphertext>.<base64_tag>
    """
    master_key = bytes.fromhex(encryption_key_hex)
    salt = os.urandom(16)  # 16-байтная соль
    derived_key = derive_key(master_key, salt)

    nonce = os.urandom(GCM_NONCE_LENGTH)
    encryptor = Cipher(
        algorithms.AES(derived_key),
        modes.GCM(nonce)
    ).encryptor()

    cipher_text = encryptor.update(plain_text.encode('utf-8')) + encryptor.finalize()
    tag = encryptor.tag

    # Собираем все части в одну строку, кодируем в URL-safe base64 и разделяем точками
    return f"{urlsafe_b64encode(salt).decode('utf-8')}." \
           f"{urlsafe_b64encode(nonce).decode('utf-8')}." \
           f"{urlsafe_b64encode(cipher_text).decode('utf-8')}." \
           f"{urlsafe_b64encode(tag).decode('utf-8')}"

def decrypt_data(encrypted_text: str, encryption_key_hex: str) -> str:
    """
    Дешифрует строку, зашифрованную с использованием AES-256-GCM.

    Исключения:
        DecryptionError: Если не пройдена аутентификация (неверный ключ/поврежденные данные)
                         или формат данных некорректен.
    """
    parts = encrypted_text.split('.')
    if len(parts) != 4:
        raise DecryptionError("Некорректный формат зашифрованных данных")

    try:
        salt = urlsafe_b64decode(parts[0])
        nonce = urlsafe_b64decode(parts[1])
        cipher_text = urlsafe_b64decode(parts[2])
        tag = urlsafe_b64decode(parts[3])
    except Exception as e:
        raise DecryptionError("Ошибка декодирования base64 частей зашифрованных данных") from e

    master_key = bytes.fromhex(encryption_key_hex)
    derived_key = derive_key(master_key, salt)

    decryptor = Cipher(
        algorithms.AES(derived_key),
        modes.GCM(nonce, tag)
    ).decryptor()

    try:
        plain_text_bytes = decryptor.update(cipher_text) + decryptor.finalize()
        return plain_text_bytes.decode('utf-8')
    except InvalidTag:
        raise DecryptionError("Ошибка аутентификации данных. Вероятная причина: неверный ключ шифрования.")
    except Exception as e:
        raise DecryptionError(f"Произошла непредвиденная ошибка при дешифровании: {e}") from e