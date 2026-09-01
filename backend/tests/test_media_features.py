"""
test_media_features.py: Comprehensive test suite for media attachments
(voice notes, photos) across models, media_store, HTTP victim plane,
authenticated API plane, and DTN sync engine.
"""

import io
import json
import pytest
from fastapi.testclient import TestClient

import config
import crypto_keys
import media_store
import models
import sync_engine
from api import app as auth_app
from http_app import app as public_app


@pytest.fixture(autouse=True)
def clean_db(tmp_path, monkeypatch):
    db = str(tmp_path / "test_mesh.db")
    media = str(tmp_path / "media")
    monkeypatch.setattr(config, "DB_FILE", db)
    monkeypatch.setattr(models, "DB_FILE", db)
    monkeypatch.setattr(config, "MEDIA_DIR", media)
    models.init_db()
    yield


def test_media_attachment_signing_and_verification():
    rec = models.save_media_attachment(
        parent_table="messages",
        parent_id="msg-123",
        filename="voice_note.m4a",
        mime_type="audio/m4a",
        size_bytes=1024,
        sha256="abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
    )
    assert rec["id"]
    assert rec["signature"]
    assert models.verify_record("media_attachments", rec)

    # Tamper with filename
    tampered = dict(rec)
    tampered["filename"] = "hacked.exe"
    assert not models.verify_record("media_attachments", tampered)

    # Tamper with sha256
    tampered2 = dict(rec)
    tampered2["sha256"] = "0000000000000000000000000000000000000000000000000000000000000000"
    assert not models.verify_record("media_attachments", tampered2)


def test_media_store_blob_operations():
    data = b"RIFF....WAVEfmt ....data....voice_sample_audio"
    mid = "media-test-1"

    sha = media_store.save_blob(mid, data)
    assert sha == media_store.compute_sha256(data)
    assert media_store.has_blob(mid)
    assert media_store.get_blob(mid) == data
    assert media_store.verify_blob(mid, sha)
    assert not media_store.verify_blob(mid, "wrong_hash")

    # Exceed size limit
    big_data = b"x" * (config.MAX_MEDIA_SIZE + 100)
    with pytest.raises(ValueError):
        media_store.save_blob("big-media", big_data)


def test_public_checkin_with_media():
    client = TestClient(public_app)

    audio_bytes = b"FAKE_AAC_AUDIO_DATA_FOR_SOS"
    checkin_payload = {
        "device_id": "victim-phone-42",
        "sos": True,
        "sos_text": "Trapped under debris with injured person",
        "points": [
            {"lat": 6.9271, "lon": 79.8612, "accuracy": 5.0, "recorded_at": "2026-09-02T02:00:00.000000Z"}
        ],
    }

    files = {
        "media": ("sos_audio.m4a", io.BytesIO(audio_bytes), "audio/m4a"),
    }
    data = {
        "checkin_json": json.dumps(checkin_payload),
    }

    resp = client.post("/checkin-with-media", data=data, files=files)
    assert resp.status_code == 200, resp.text
    res_json = resp.json()
    assert res_json["stored"] == 1
    assert res_json["sos_msg_id"] is not None
    assert res_json["media_id"] is not None
    media_id = res_json["media_id"]

    # Verify message in DB has the attachment
    msg = models.get_message_by_id(res_json["sos_msg_id"])
    assert msg is not None
    assert len(msg["attachments"]) == 1
    assert msg["attachments"][0]["id"] == media_id
    assert msg["attachments"][0]["mime_type"] == "audio/m4a"

    # Verify conversation for victim device returns the message with attachment
    convo = models.get_conversation("victim-phone-42")
    assert len(convo["messages"]) == 1
    assert len(convo["messages"][0]["attachments"]) == 1
    assert convo["messages"][0]["attachments"][0]["id"] == media_id

    # Retrieve media from public GET /media/{id}
    media_resp = client.get(f"/media/{media_id}")
    assert media_resp.status_code == 200
    assert media_resp.content == audio_bytes
    assert media_resp.headers["content-type"] == "audio/m4a"


def test_public_checkin_media_rejections():
    client = TestClient(public_app)

    # Unsupported MIME type
    bad_file = io.BytesIO(b"bad_script")
    data = {
        "checkin_json": json.dumps({
            "device_id": "victim-dev-1",
            "sos": True,
            "sos_text": "SOS",
            "points": [],
        }),
    }
    resp = client.post("/checkin-with-media", data=data, files={"media": ("test.exe", bad_file, "application/x-msdownload")})
    assert resp.status_code == 415

    # File exceeding MAX_MEDIA_SIZE
    huge_file = io.BytesIO(b"0" * (config.MAX_MEDIA_SIZE + 500))
    resp = client.post("/checkin-with-media", data=data, files={"media": ("huge.jpg", huge_file, "image/jpeg")})
    assert resp.status_code == 413


def test_authenticated_gs_uplink_with_media_and_retrieval():
    client = TestClient(auth_app)
    headers = {"X-API-Key": config.RESCUE_API_KEY}

    photo_bytes = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01test_jpeg_photo_content"
    data = {
        "content": "Found bridge washed away, clearing debris",
        "sender": "TEAM_BRAVO",
        "location_lat": "6.9275",
        "location_lon": "79.8620",
    }
    files = {
        "media": ("bridge_photo.jpg", io.BytesIO(photo_bytes), "image/jpeg"),
    }

    resp = client.post("/gs-uplink-with-media", data=data, files=files, headers=headers)
    assert resp.status_code == 200, resp.text
    res_json = resp.json()
    assert res_json["msg_id"]
    assert res_json["media_id"]
    media_id = res_json["media_id"]

    # Verify attachment in DB
    att = models.get_media_attachment(media_id)
    assert att is not None
    assert att["parent_table"] == "gs_messages"
    assert att["parent_id"] == res_json["msg_id"]

    # Retrieve media through auth API GET /media/{id}
    get_resp = client.get(f"/media/{media_id}", headers=headers)
    assert get_resp.status_code == 200
    assert get_resp.content == photo_bytes
    assert get_resp.headers["content-type"] == "image/jpeg"


def test_media_dtn_sync_flow():
    # Simulate peer having a media attachment and blob
    client = TestClient(auth_app)
    sync_headers = {"X-Node-Auth": crypto_keys.NODE_AUTH_VALUE}

    photo_data = b"REAL_IMAGE_BYTES_REPLICATING_ACROSS_DRONES"
    mid = "remote-media-999"
    sha = media_store.save_blob(mid, photo_data)

    models.save_media_attachment(
        parent_table="messages",
        parent_id="remote-msg-1",
        filename="remote_photo.jpg",
        mime_type="image/jpeg",
        size_bytes=len(photo_data),
        sha256=sha,
        media_id=mid,
        node_id="DRONE_B",
    )

    # 1. Delta metadata sync endpoint /sync/media-attachments
    sync_resp = client.get("/sync/media-attachments", headers=sync_headers)
    assert sync_resp.status_code == 200
    rows = sync_resp.json()
    assert len(rows) == 1
    assert rows[0]["id"] == mid

    # 2. Blob sync endpoint /sync/media-blob/{id}
    blob_resp = client.get(f"/sync/media-blob/{mid}", headers=sync_headers)
    assert blob_resp.status_code == 200
    assert blob_resp.content == photo_data

    # 3. Test sync_engine ingest and blob fetching
    ingest_result = sync_engine.ingest_media_attachment(rows[0], "DRONE_B")
    assert ingest_result in ("inserted", "kept")
