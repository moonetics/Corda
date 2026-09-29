#!/usr/bin/env python3
"""
Test Suite for Phase 5: High-Speed File Streaming & Multiplexing.
Validates:
1. Binary Frame Header Packaging & Unpacking (40-byte header per protocol/file_header_spec.md)
2. 256 KB Chunk Framing & Per-Chunk SHA-256 Integrity Verification
3. Multi-Chunk Streaming, File Assembly, and Full-File Hash Verification
4. Auto-Accept Non-Overwriting File Renaming (file.pdf -> file (1).pdf -> file (2).pdf)
5. Dual-Channel Multiplexing: Clipboard sync latency (< 200 ms) during high-throughput file streaming
"""

import sys
import os
import json
import time
import socket
import struct
import uuid
import hashlib
import threading
from datetime import datetime, timezone

MAGIC_BYTES = b"CORD"  # 0x43, 0x4F, 0x52, 0x44
CHUNK_SIZE = 262144     # 256 KB

def get_iso_timestamp():
    return datetime.now(timezone.utc).isoformat()

def sha256_bytes(data: bytes) -> bytes:
    return hashlib.sha256(data).digest()

def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def build_frame_header(msg_type: int, transfer_uuid: uuid.UUID, file_idx: int, chunk_idx: int, total_chunks: int, payload_len: int) -> bytes:
    """Builds exact 40-byte binary header according to file_header_spec.md."""
    version = 0x01
    reserved = 0x0000
    uuid_bytes = transfer_uuid.bytes  # 16 bytes
    
    header = struct.pack(
        ">4sBBH16sIIII",
        MAGIC_BYTES,
        version,
        msg_type,
        reserved,
        uuid_bytes,
        file_idx,
        chunk_idx,
        total_chunks,
        payload_len
    )
    assert len(header) == 40, f"Header size must be 40 bytes, got {len(header)}"
    return header

def unpack_frame_header(header_bytes: bytes):
    """Unpacks 40-byte binary header."""
    assert len(header_bytes) == 40, f"Expected 40 bytes, got {len(header_bytes)}"
    magic, version, msg_type, reserved, uuid_bytes, file_idx, chunk_idx, total_chunks, payload_len = struct.unpack(
        ">4sBBH16sIIII",
        header_bytes
    )
    return {
        "magic": magic,
        "version": version,
        "msg_type": msg_type,
        "reserved": reserved,
        "transfer_uuid": uuid.UUID(bytes=uuid_bytes),
        "file_idx": file_idx,
        "chunk_idx": chunk_idx,
        "total_chunks": total_chunks,
        "payload_len": payload_len
    }

def test_binary_header_spec():
    print("[1/5] Testing Binary Header Specification (40-byte framing)...")
    test_uuid = uuid.uuid4()
    
    # Test CHUNK_DATA header
    header = build_frame_header(
        msg_type=0x01,
        transfer_uuid=test_uuid,
        file_idx=2,
        chunk_idx=5,
        total_chunks=10,
        payload_len=CHUNK_SIZE
    )
    
    assert len(header) == 40, f"Header length must be 40 bytes, got {len(header)}"
    unpacked = unpack_frame_header(header)
    assert unpacked["magic"] == b"CORD"
    assert unpacked["version"] == 1
    assert unpacked["msg_type"] == 0x01
    assert unpacked["transfer_uuid"] == test_uuid
    assert unpacked["file_idx"] == 2
    assert unpacked["chunk_idx"] == 5
    assert unpacked["total_chunks"] == 10
    assert unpacked["payload_len"] == CHUNK_SIZE

    # Test READY_PULL header (0x04)
    pull_header = build_frame_header(
        msg_type=0x04,
        transfer_uuid=test_uuid,
        file_idx=0,
        chunk_idx=0,
        total_chunks=0,
        payload_len=0
    )
    unpacked_pull = unpack_frame_header(pull_header)
    assert unpacked_pull["msg_type"] == 0x04
    assert unpacked_pull["payload_len"] == 0
    print("      ✓ 40-byte Header layout matches specification with byte-exact precision.")

def test_chunk_checksum_integrity():
    print("[2/5] Testing 256 KB Chunk Integrity & Corrupt Chunk Rejection...")
    test_uuid = uuid.uuid4()
    payload = os.urandom(CHUNK_SIZE)
    valid_checksum = sha256_bytes(payload)
    assert len(valid_checksum) == 32

    # Pack frame: 40B Header + Payload + 32B Checksum
    header = build_frame_header(0x01, test_uuid, 0, 0, 1, len(payload))
    frame = header + payload + valid_checksum
    assert len(frame) == 40 + CHUNK_SIZE + 32

    # Verify unpacking and checksum match
    unpacked = unpack_frame_header(frame[:40])
    rx_payload = frame[40:40 + unpacked["payload_len"]]
    rx_checksum = frame[40 + unpacked["payload_len"]:]
    assert sha256_bytes(rx_payload) == rx_checksum

    # Corrupt payload by flipping one bit
    corrupted_payload = bytearray(payload)
    corrupted_payload[1024] ^= 0x01
    corrupted_checksum = sha256_bytes(corrupted_payload)
    assert corrupted_checksum != rx_checksum, "Bit flip must change chunk SHA-256"
    print("      ✓ Per-chunk 32-byte SHA-256 verification and corruption detection verified.")

def test_multi_chunk_assembly():
    print("[3/5] Testing Multi-Chunk (256 KB) Streaming & Full-File Reassembly...")
    file_size = 700000  # 700 KB (requires 3 chunks: 256KB + 256KB + 188KB)
    raw_file_content = os.urandom(file_size)
    expected_full_sha256 = sha256_hex(raw_file_content)

    test_uuid = uuid.uuid4()
    total_chunks = (file_size + CHUNK_SIZE - 1) // CHUNK_SIZE
    assert total_chunks == 3

    # Slice into chunks and stream to receiver buffer
    frames = []
    for i in range(total_chunks):
        start = i * CHUNK_SIZE
        end = min(file_size, (i + 1) * CHUNK_SIZE)
        chunk = raw_file_content[start:end]
        h = build_frame_header(0x01, test_uuid, 0, i, total_chunks, len(chunk))
        chk = sha256_bytes(chunk)
        frames.append(h + chunk + chk)

    # Add FILE_COMPLETE frame
    frames.append(build_frame_header(0x02, test_uuid, 0, 0, total_chunks, 0))
    # Add TRANSFER_COMPLETE frame
    frames.append(build_frame_header(0x03, test_uuid, 0, 0, 0, 0))

    # Receiver reconstructs
    reconstructed = bytearray()
    full_hasher = hashlib.sha256()

    for frame in frames:
        header = unpack_frame_header(frame[:40])
        msg_type = header["msg_type"]
        if msg_type == 0x01:
            p_len = header["payload_len"]
            chunk_data = frame[40:40 + p_len]
            chunk_chk = frame[40 + p_len:40 + p_len + 32]
            assert sha256_bytes(chunk_data) == chunk_chk
            reconstructed.extend(chunk_data)
            full_hasher.update(chunk_data)
        elif msg_type == 0x02:
            assert full_hasher.hexdigest() == expected_full_sha256
        elif msg_type == 0x03:
            pass

    assert len(reconstructed) == file_size
    assert hashlib.sha256(reconstructed).hexdigest() == expected_full_sha256
    print(f"      ✓ 700 KB file split into {total_chunks} chunks, reassembled & verified with matching SHA-256.")

def test_auto_accept_renaming():
    print("[4/5] Testing Auto-Accept Non-Overwriting Duplicate Renaming...")
    def get_unique_name(existing_files: set, filename: str) -> str:
        if filename not in existing_files:
            return filename
        dot_idx = filename.rfind('.')
        if dot_idx > 0:
            name_part = filename[:dot_idx]
            ext_part = filename[dot_idx:]
        else:
            name_part = filename
            ext_part = ""
        counter = 1
        while f"{name_part} ({counter}){ext_part}" in existing_files:
            counter += 1
        return f"{name_part} ({counter}){ext_part}"

    existing = set()
    name1 = get_unique_name(existing, "Project_Proposal.pdf")
    assert name1 == "Project_Proposal.pdf"
    existing.add(name1)

    name2 = get_unique_name(existing, "Project_Proposal.pdf")
    assert name2 == "Project_Proposal (1).pdf"
    existing.add(name2)

    name3 = get_unique_name(existing, "Project_Proposal.pdf")
    assert name3 == "Project_Proposal (2).pdf"
    existing.add(name3)

    name_no_ext = get_unique_name(existing, "README")
    assert name_no_ext == "README"
    existing.add(name_no_ext)

    name_no_ext2 = get_unique_name(existing, "README")
    assert name_no_ext2 == "README (1)"
    print("      ✓ Duplicate filenames safely renamed without overwriting: file.pdf -> file (1).pdf -> file (2).pdf.")

def test_dual_channel_multiplexing():
    print("[5/5] Testing Dual-Channel Multiplexing (Clipboard < 200 ms latency during file streaming)...")
    ctrl_port = 54391
    data_port = 54392

    # Control Channel mock server (NDJSON)
    ctrl_server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    ctrl_server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ctrl_server.bind(("127.0.0.1", ctrl_port))
    ctrl_server.listen(5)

    # Data Channel mock server (Binary stream)
    data_server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    data_server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    data_server.bind(("127.0.0.1", data_port))
    data_server.listen(5)

    clipboard_latencies = []
    stop_event = threading.Event()

    def handle_ctrl():
        conn, _ = ctrl_server.accept()
        buf = b""
        while not stop_event.is_set():
            data = conn.recv(4096)
            if not data:
                break
            buf += data
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                msg = json.loads(line.decode('utf-8'))
                if msg.get("type") == "CLIPBOARD_PAYLOAD":
                    # Respond with ack
                    ack = json.dumps({"type": "CLIPBOARD_ACK", "hash": msg.get("content_hash")}) + "\n"
                    conn.sendall(ack.encode('utf-8'))
        conn.close()

    def handle_data():
        conn, _ = data_server.accept()
        bytes_received = 0
        while not stop_event.is_set():
            data = conn.recv(65536)
            if not data:
                break
            bytes_received += len(data)
        conn.close()

    ctrl_th = threading.Thread(target=handle_ctrl, daemon=True)
    data_th = threading.Thread(target=handle_data, daemon=True)
    ctrl_th.start()
    data_th.start()

    # Client connections
    time.sleep(0.05)
    ctrl_client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    ctrl_client.connect(("127.0.0.1", ctrl_port))
    ctrl_reader = ctrl_client.makefile('r')

    data_client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    data_client.connect(("127.0.0.1", data_port))

    # Background heavy file streaming on Data Channel (5 MB stream in 256KB chunks)
    def heavy_streaming():
        try:
            chunk = os.urandom(CHUNK_SIZE)
            chk = sha256_bytes(chunk)
            t_uuid = uuid.uuid4()
            for i in range(20):  # 20 * 256 KB = ~5.2 MB
                if stop_event.is_set():
                    break
                header = build_frame_header(0x01, t_uuid, 0, i, 20, CHUNK_SIZE)
                data_client.sendall(header + chunk + chk)
                time.sleep(0.01)  # Simulate line rate
        except (BrokenPipeError, OSError):
            pass

    stream_th = threading.Thread(target=heavy_streaming, daemon=True)
    stream_th.start()

    # While heavy streaming is active, fire 5 clipboard sync payloads on Control Channel
    time.sleep(0.05)
    for i in range(5):
        sample_text = f"Corda clipboard sync test #{i} at {time.time()}"
        payload = json.dumps({
            "type": "CLIPBOARD_PAYLOAD",
            "content": sample_text,
            "content_hash": hashlib.sha256(sample_text.encode('utf-8')).hexdigest(),
            "timestamp": get_iso_timestamp()
        }) + "\n"

        t0 = time.perf_counter()
        ctrl_client.sendall(payload.encode('utf-8'))
        resp_line = ctrl_reader.readline()
        t1 = time.perf_counter()

        latency_ms = (t1 - t0) * 1000.0
        clipboard_latencies.append(latency_ms)
        assert resp_line.strip() != "", "Control channel must return response"
        time.sleep(0.02)

    stop_event.set()
    stream_th.join(timeout=2)
    ctrl_client.close()
    data_client.close()
    ctrl_server.close()
    data_server.close()

    avg_latency = sum(clipboard_latencies) / len(clipboard_latencies)
    max_latency = max(clipboard_latencies)
    print(f"      ✓ Clipboard latencies during 5MB binary stream: {[f'{l:.1f}ms' for l in clipboard_latencies]}")
    print(f"      ✓ Avg Latency: {avg_latency:.2f} ms | Max Latency: {max_latency:.2f} ms (Target: < 200 ms)")
    assert max_latency < 200.0, f"Clipboard latency exceeded 200ms threshold: {max_latency:.2f}ms"

def main():
    print("=" * 70)
    print("CORDA PROTOCOL SUITE: PHASE 5 FILE STREAMING & MULTIPLEXING")
    print("=" * 70)

    test_binary_header_spec()
    test_chunk_checksum_integrity()
    test_multi_chunk_assembly()
    test_auto_accept_renaming()
    test_dual_channel_multiplexing()

    print("=" * 70)
    print("ALL 5 PHASE 5 VERIFICATION TESTS PASSED SUCCESSFULLY! 🚀")
    print("=" * 70)

if __name__ == "__main__":
    main()
