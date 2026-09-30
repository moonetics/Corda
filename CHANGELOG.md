# Changelog

All notable changes to **Corda** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.3.0] - 2026-10-01

### Added
- **Bidirectional Bonjour / mDNS Discovery**:
  - Registered native Android `NsdManager.registerService()` in `CordaForegroundService` broadcasting `_corda._tcp` alongside client browsing, enabling macOS to instantly find nearby Android phones.
  - Enhanced macOS `BonjourDiscoveryManager` to immediately resolve endpoints with graceful TXT attribute parsing and deduplication across network interfaces.
  - Added dynamic companion state in macOS Devices tab showing **Ready to Pair**, **Trusted Companion**, or **Connected**.
- **Apple Continuity Notification Mirroring & Filtering**:
  - Balanced Android settings UI with **All App Notification** and **All System Notification** sibling cards.
  - Added native test alert delivery mechanism on macOS supporting both `UNUserNotificationCenter` and `NSAppleScript` fallbacks.

### Fixed
- **Large File & Image Streaming Stalls**: Implemented recursive `readExact` TCP accumulator on macOS `FileStreamingManager` to prevent byte buffer truncation and transfer stalls.
- **macOS Bundle Signing**: Automated ad-hoc code-signing in `Makefile` to allow native macOS notification authorization without requiring manual certificate installation.

---

## [1.1.0] - 2026-09-30

### Added
- **Universal File & Image Clipboard Synchronization**:
  - Automatically streams copied files and images (up to 50MB) between macOS and Android over high-speed local Wi-Fi in the background.
  - **macOS Finder & App Integration**: Injects received files into `NSPasteboard.general` as native `NSURL` (`.fileURL`), `NSFilenamesPboardType`, and `NSImage`. Pasting (`Cmd+V`) in Finder duplicates the actual file; pasting in Messages, Slack, Telegram, or Photoshop inserts the real image or file attachment directly.
  - **Android FileProvider Integration**: Configured `androidx.core.content.FileProvider` (`com.corda.app.fileprovider`) and `ClipData.newUri` with `FLAG_GRANT_READ_URI_PERMISSION`. Pasting ("Tempel") in WhatsApp, Telegram, Samsung Notes, or document editors pastes the actual file/photo instead of a file path text string.
  - **Protocol Extension**: Added `CLIPBOARD_FILE_ANNOUNCE` to formal JSON Schema (`protocol/control_messages.json`) with automated validator coverage (`scripts/validate_schemas.py`).
  - **Tactile Haptic Feedback**: Subtle vibration tick (`VibrationEffect.EFFECT_TICK`) on Android when an incoming clipboard file/image is ready to paste.
  - **Loop Suppression**: SHA-256 content deduplication prevents bidirectional echo loops for binary streams.

### Changed
- Refactored `MacClipboardObserver` to detect Finder file copies and raw image buffers alongside plain text.
- Enhanced `ClipboardAccessibilityService` and `TransparentClipboardReaderActivity` to sniff URI-based clipboard items directly from Gallery and Files apps.
- Updated documentation and licenses to reflect open-source release specifications.

---

## [1.0.0] - 2026-09-29

### Added
- **Initial Release of Corda** — The invisible cord between your Mac and Android:
  - **Zero-Touch Background Clipboard Sync**: Bi-directional, real-time text synchronization between macOS and Android without requiring either app to stay in the foreground.
  - **Multi-Layer Android Sniffer Engine**: Captures copies from system menus, Gboard/Samsung Keyboard, custom in-app copy buttons (password managers, banking apps, Seakun), and toast/snackbar alerts via Accessibility Services and BAL-exempt activities.
  - **High-Speed Chunked File Streaming**: Dedicated binary data socket on port `54322` streaming 256KB chunks over local Wi-Fi with dual SHA-256 integrity verification.
  - **Dual-Channel Socket Architecture**:
    - Port `54321`: NDJSON Control Channel (pairing, clipboard sync, heartbeat).
    - Port `54322`: Binary streaming channel for large files.
    - Zero configuration local discovery via mDNS / Bonjour (`_corda._tcp.local.`).
  - **Hardware-Pinned Security**: Ed25519/X25519 public key exchange via QR code pairing with one-time 6-digit PIN. In-band SHA-256 fingerprint authentication prevents unauthorized injection.
  - **100% Local & Zero Cloud**: Zero remote servers, zero user accounts, zero analytics or telemetry tracking.
  - **Native macOS Menu Bar App**: Pure Swift and SwiftUI implementation living unobtrusively in the menu bar with recent clipboard history and device status.
  - **Modern Android Mobile App**: Flutter front-end combined with native Kotlin services, Material 3 + Cupertino design harmonization, Quick Settings tile, and adaptive launcher icons.
