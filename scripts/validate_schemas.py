#!/usr/bin/env python3
"""
Zero-dependency validator for Corda protocol JSON schema and sample messages.
"""

import json
import re
import sys
from datetime import datetime

def is_valid_iso8601(val: str) -> bool:
    try:
        if val.endswith("Z"):
            val = val[:-1] + "+00:00"
        datetime.fromisoformat(val)
        return True
    except Exception:
        return False

def is_valid_uuid(val: str) -> bool:
    pattern = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
    return bool(pattern.match(val))

def is_valid_fingerprint(val: str) -> bool:
    pattern = re.compile(r"^([0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$")
    return bool(pattern.match(val))

def is_valid_sha256(val: str) -> bool:
    pattern = re.compile(r"^[0-9a-fA-F]{64}$")
    return bool(pattern.match(val))

def validate_message(msg: dict, schema: dict) -> None:
    msg_type = msg.get("type")
    assert msg_type, "Message missing 'type'"
    assert is_valid_iso8601(msg.get("timestamp", "")), f"Invalid timestamp format in {msg_type}"

    definitions = schema["definitions"]

    if msg_type == "PAIR_REQUEST":
        def_spec = definitions["PairRequest"]
        for req in def_spec["required"]:
            assert req in msg, f"Missing required field {req} in PAIR_REQUEST"
        assert is_valid_uuid(msg["device_id"]), "Invalid device_id UUID"
        assert msg["platform"] in ["macos", "android"], "Invalid platform"
        assert is_valid_fingerprint(msg["fingerprint"]), "Invalid fingerprint format"
        assert re.match(r"^[0-9]{6}$", msg["pin"]), "PIN must be 6 numeric digits"

    elif msg_type == "PAIR_RESPONSE":
        def_spec = definitions["PairResponse"]
        for req in def_spec["required"]:
            assert req in msg, f"Missing required field {req} in PAIR_RESPONSE"
        assert is_valid_uuid(msg["device_id"]), "Invalid device_id UUID"
        assert msg["status"] in ["ACCEPTED", "REJECTED", "PIN_MISMATCH"], "Invalid status"
        assert is_valid_fingerprint(msg["fingerprint"]), "Invalid fingerprint format"

    elif msg_type == "CLIPBOARD_PAYLOAD":
        def_spec = definitions["ClipboardPayload"]
        for req in def_spec["required"]:
            assert req in msg, f"Missing required field {req} in CLIPBOARD_PAYLOAD"
        assert msg["content_type"] in ["text/plain", "text/uri-list"], "Invalid content_type"
        assert is_valid_sha256(msg["content_hash"]), "Invalid content_hash SHA256"

    elif msg_type == "HEARTBEAT_PING":
        assert isinstance(msg.get("seq"), int) and msg["seq"] >= 0, "Invalid seq in HEARTBEAT_PING"

    elif msg_type == "HEARTBEAT_PONG":
        assert isinstance(msg.get("seq"), int) and msg["seq"] >= 0, "Invalid seq in HEARTBEAT_PONG"

    elif msg_type == "FILE_METADATA_HEADER":
        assert is_valid_uuid(msg["transfer_id"]), "Invalid transfer_id UUID"
        assert isinstance(msg["total_files"], int) and msg["total_files"] >= 1
        assert isinstance(msg["total_bytes"], int) and msg["total_bytes"] >= 0
        assert isinstance(msg["files"], list) and len(msg["files"]) == msg["total_files"]
        for f in msg["files"]:
            assert f.get("name"), "File item missing name"
            assert isinstance(f.get("size_bytes"), int) and f["size_bytes"] >= 0
            assert is_valid_sha256(f.get("sha256", "")), f"Invalid file sha256 for {f.get('name')}"

    elif msg_type == "FILE_TRANSFER_ABORT":
        assert is_valid_uuid(msg["transfer_id"]), "Invalid transfer_id UUID"
        assert msg.get("reason"), "Missing reason in abort message"

    elif msg_type == "CLIPBOARD_FILE_ANNOUNCE":
        def_spec = definitions["ClipboardFileAnnounce"]
        for req in def_spec["required"]:
            assert req in msg, f"Missing required field {req} in CLIPBOARD_FILE_ANNOUNCE"
        assert is_valid_uuid(msg["transfer_id"]), "Invalid transfer_id UUID"
        assert msg.get("file_name"), "Missing file_name in CLIPBOARD_FILE_ANNOUNCE"
        assert msg.get("mime_type"), "Missing mime_type in CLIPBOARD_FILE_ANNOUNCE"
        assert isinstance(msg.get("size_bytes"), int) and 1 <= msg["size_bytes"] <= 52428800, "size_bytes must be between 1 and 50MB"
        assert is_valid_sha256(msg.get("sha256", "")), "Invalid sha256 in CLIPBOARD_FILE_ANNOUNCE"

    elif msg_type == "OTP_DETECTED":
        def_spec = definitions["OtpDetected"]
        for req in def_spec["required"]:
            assert req in msg, f"Missing required field {req} in OTP_DETECTED"
        assert is_valid_uuid(msg["device_id"]), "Invalid device_id UUID"
        assert re.match(r"^[0-9]{4,8}$", msg["code"]), "Invalid OTP code format"
        assert 10 <= msg["expires_in"] <= 300, "Invalid expires_in range"
        # Strict privacy assertion: ensure no raw message body is present!
        assert "message_text" not in msg, "Privacy violation: message_text found in OTP_DETECTED"
        assert "full_sms_body" not in msg, "Privacy violation: full_sms_body found in OTP_DETECTED"

    elif msg_type == "BATTERY_STATUS":
        def_spec = definitions["BatteryStatus"]
        for req in def_spec["required"]:
            assert req in msg, f"Missing required field {req} in BATTERY_STATUS"
        assert is_valid_uuid(msg["device_id"]), "Invalid device_id UUID"
        assert 0 <= msg["level"] <= 100, "Invalid battery level"
        assert isinstance(msg["is_charging"], bool), "is_charging must be boolean"
        assert msg["power_source"] in ["battery", "ac", "usb", "wireless"], "Invalid power source"

    elif msg_type == "NOTIFICATION_MIRROR":
        required = ["type", "device_id", "notification_id", "package_name", "app_name", "title", "text", "timestamp"]
        for field in required:
            assert field in msg, f"Missing required field {field}"
        assert isinstance(msg["title"], str), "title must be a string"
        assert isinstance(msg["text"], str), "text must be a string"
        assert isinstance(msg["package_name"], str), "package_name must be a string"
        assert isinstance(msg["app_name"], str), "app_name must be a string"

    elif msg_type == "NOTIFICATION_WHITELIST_SYNC":
        required = ["type", "device_id", "master_enabled", "apps", "timestamp"]
        for field in required:
            assert field in msg, f"Missing required field {field}"
        assert isinstance(msg["master_enabled"], bool), "master_enabled must be boolean"
        assert isinstance(msg["apps"], list), "apps must be a list"
        for app in msg["apps"]:
            assert "package_name" in app and isinstance(app["package_name"], str)
            assert "app_name" in app and isinstance(app["app_name"], str)
            assert "is_enabled" in app and isinstance(app["is_enabled"], bool)

    else:
        raise ValueError(f"Unknown message type: {msg_type}")

def main():
    schema_path = "protocol/control_messages.json"
    print(f"Reading schema: {schema_path}...")
    with open(schema_path, "r", encoding="utf-8") as f:
        schema = json.load(f)

    # Sample messages to validate against schema definitions
    sample_messages = [
        {
            "type": "PAIR_REQUEST",
            "device_id": "a1b2c3d4-e5f6-4a1b-8c2d-3e4f5a6b7c8d",
            "device_name": "MacBook Pro M3",
            "platform": "macos",
            "public_key": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...",
            "fingerprint": "12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF",
            "pin": "847291",
            "timestamp": "2026-09-29T14:15:00.000Z"
        },
        {
            "type": "PAIR_RESPONSE",
            "device_id": "99887766-5544-4321-abcd-ef0123456789",
            "device_name": "Pixel 8 Pro",
            "platform": "android",
            "public_key": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...",
            "fingerprint": "FE:DC:BA:09:87:65:43:21:FE:DC:BA:09:87:65:43:21:FE:DC:BA:09:87:65:43:21:FE:DC:BA:09:87:65:43:21",
            "status": "ACCEPTED",
            "timestamp": "2026-09-29T14:15:02.100Z"
        },
        {
            "type": "CLIPBOARD_PAYLOAD",
            "content": "https://github.com/corda/app",
            "content_type": "text/plain",
            "content_hash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "timestamp": "2026-09-29T14:15:05.500Z"
        },
        {
            "type": "HEARTBEAT_PING",
            "seq": 42,
            "timestamp": "2026-09-29T14:15:20.000Z"
        },
        {
            "type": "HEARTBEAT_PONG",
            "seq": 42,
            "timestamp": "2026-09-29T14:15:20.015Z"
        },
        {
            "type": "FILE_METADATA_HEADER",
            "transfer_id": "11223344-5566-7788-99aa-bbccddeeff00",
            "total_files": 2,
            "total_bytes": 10485760,
            "files": [
                {
                    "name": "Project_Design.pdf",
                    "relative_path": "Project_Design.pdf",
                    "size_bytes": 5242880,
                    "sha256": "4b227777d4dd1fc61c6f884f48641d02b4d121d3fd328cb08b5531fcacdabf8a"
                },
                {
                    "name": "screenshot.png",
                    "relative_path": "screenshot.png",
                    "size_bytes": 5242880,
                    "sha256": "ef2d127de37b942baad06145e54b0c619a1f22327b2ebbcfbec78f5564afe39d"
                }
            ],
            "timestamp": "2026-09-29T14:16:00.000Z"
        },
        {
            "type": "FILE_TRANSFER_ABORT",
            "transfer_id": "11223344-5566-7788-99aa-bbccddeeff00",
            "reason": "Cancelled by user on macOS",
            "timestamp": "2026-09-29T14:16:02.500Z"
        },
        {
            "type": "CLIPBOARD_FILE_ANNOUNCE",
            "transfer_id": "33445566-7788-99aa-bbcc-ddeeff001122",
            "file_name": "shared_image.png",
            "mime_type": "image/png",
            "size_bytes": 2048000,
            "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "timestamp": "2026-09-29T14:17:00.000Z"
        },
        {
            "type": "OTP_DETECTED",
            "device_id": "8899aabb-ccdd-eeff-0011-223344556677",
            "service_name": "BCA",
            "code": "492015",
            "expires_in": 60,
            "timestamp": "2026-09-30T12:00:00.000Z"
        },
        {
            "type": "BATTERY_STATUS",
            "device_id": "8899aabb-ccdd-eeff-0011-223344556677",
            "level": 85,
            "is_charging": True,
            "power_source": "ac",
            "timestamp": "2026-09-30T12:00:05.000Z"
        },
        {
            "type": "NOTIFICATION_MIRROR",
            "device_id": "8899aabb-ccdd-eeff-0011-223344556677",
            "notification_id": "notif_1092837",
            "package_name": "com.whatsapp",
            "app_name": "WhatsApp",
            "title": "Budi Santoso",
            "text": "Besok meeting jam 10 ya di kantor",
            "timestamp": "2026-09-30T12:00:10.000Z"
        },
        {
            "type": "NOTIFICATION_WHITELIST_SYNC",
            "device_id": "8899aabb-ccdd-eeff-0011-223344556677",
            "master_enabled": True,
            "apps": [
                {
                    "package_name": "com.whatsapp",
                    "app_name": "WhatsApp",
                    "is_enabled": True
                },
                {
                    "package_name": "org.telegram.messenger",
                    "app_name": "Telegram",
                    "is_enabled": True
                }
            ],
            "timestamp": "2026-09-30T12:00:15.000Z"
        }
    ]

    for sample in sample_messages:
        m_type = sample["type"]
        validate_message(sample, schema)
        print(f"  [OK] Validated {m_type}")

    print(f"\n✅ All {len(sample_messages)} message types validated successfully against protocol definitions!")

if __name__ == "__main__":
    main()
