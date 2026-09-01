"""
media_store.py: Filesystem storage for media blobs (voice notes, images).

SQLite holds the metadata and HMAC signatures (models.media_attachments),
while raw binary blobs are stored on disk in config.MEDIA_DIR to prevent
database bloat on Raspberry Pi SD cards.

Blob integrity is tied to the signed record: each media_attachment row
includes the SHA-256 hash of the binary file, signed by K_MSG.
"""

import hashlib
import os
from pathlib import Path
from typing import Optional, Set

import config


def get_media_dir() -> Path:
    p = Path(config.MEDIA_DIR)
    if not p.is_absolute():
        p = Path(os.getcwd()) / p
    p.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(p, 0o700)
    except OSError:
        pass
    return p


def compute_sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def blob_path(media_id: str) -> Path:
    # Sanitize media_id to avoid path traversal
    safe_id = "".join(c for c in media_id if c.isalnum() or c in ("-", "_"))
    return get_media_dir() / safe_id


def has_blob(media_id: str) -> bool:
    return blob_path(media_id).is_file()


def save_blob(media_id: str, data: bytes) -> str:
    """Save binary blob to disk. Returns the SHA-256 hex digest of the saved data.
    Raises ValueError if data exceeds config.MAX_MEDIA_SIZE."""
    if len(data) > config.MAX_MEDIA_SIZE:
        raise ValueError(
            f"Media size {len(data)} exceeds maximum allowed {config.MAX_MEDIA_SIZE} bytes"
        )
    p = blob_path(media_id)
    p.write_bytes(data)
    try:
        os.chmod(p, 0o600)
    except OSError:
        pass
    return compute_sha256(data)


def get_blob(media_id: str) -> Optional[bytes]:
    """Read binary blob from disk. Returns None if file does not exist."""
    p = blob_path(media_id)
    if not p.is_file():
        return None
    return p.read_bytes()


def verify_blob(media_id: str, expected_sha256: str) -> bool:
    """Verify that blob exists on disk and matches expected SHA-256."""
    data = get_blob(media_id)
    if data is None:
        return False
    return compute_sha256(data) == expected_sha256


def delete_blob(media_id: str) -> bool:
    p = blob_path(media_id)
    if p.is_file():
        try:
            p.unlink()
            return True
        except OSError:
            return False
    return False


def prune_unreferenced_blobs(valid_media_ids: Set[str]) -> int:
    """Remove any blob on disk that is not in the set of known media_ids."""
    removed = 0
    media_dir = get_media_dir()
    for item in media_dir.iterdir():
        if item.is_file() and item.name not in valid_media_ids:
            try:
                item.unlink()
                removed += 1
            except OSError:
                pass
    return removed
