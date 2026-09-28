# Corda Protocol & Wire Specifications
## Single Source of Truth for Data Contracts

Folder ini berisi spesifikasi skema data dan format paket komunikasi bersama antara **macOS** dan **Android**:

- `control_messages.json`: Skema JSON untuk Control Channel (Port 54321) mencakup handshake pairing, sinkronisasi clipboard, dan koordinasi transfer file.
- `file_header_spec.md`: Format framing biner untuk Data Streaming Channel (Port 54322) berkecepatan tinggi dengan chunk size 256 KB.

Spesifikasi resmi akan diimplementasikan secara mendalam pada **Phase 1**.
