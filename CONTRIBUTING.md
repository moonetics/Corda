# Contributing to Corda

Thank you for your interest in contributing to Corda! We appreciate community contributions to make local cross-device continuity faster, smoother, and more reliable.

---

## 🧭 Code of Conduct

We are committed to providing a welcoming, inclusive, and harassment-free environment for everyone. Please be respectful and constructive in all discussions, pull requests, and issue reports.

---

## 🛠️ Development Setup

### System Requirements
* **macOS**: macOS 14.0 (Sonoma) or newer. Xcode 15+ and command-line tools installed.
* **Android**: Android Studio with SDK API 34+ and NDK support.
* **Flutter**: Flutter 3.19+ (stable channel).
* **Python**: Python 3.10+ for running validation scripts.

Run the sanity check command:
```bash
make check
```

---

## 🏗️ Project Architecture

* **`protocol/`**: The ground truth for network communication. If you modify message payloads or add new event types, update [protocol/control_messages.json](protocol/control_messages.json) and ensure [scripts/validate_schemas.py](scripts/validate_schemas.py) passes.
* **`macos/`**: Pure Swift package. Uses SwiftUI for menu bar UI, Network framework (`NWListener` / `NWConnection`) for low-overhead networking, and macOS Security framework for Keychain storage.
* **`android/`**: Flutter UI shell for multiplatform screens with custom Kotlin native services (`ClipboardAccessibilityService`, `CordaForegroundService`, and `ControlSocketClient`).

---

## 🧪 Running Tests & Validation

Before submitting any Pull Request, ensure that all test suites pass locally:

```bash
# 1. Validate protocol schemas
make test-protocol

# 2. Compile and test crypto and platform modules
make test-crypto

# 3. Test macOS build
make build-mac

# 4. Run automated reliability and benchmark scripts
python3 scripts/test_phase4_clipboard.py
python3 scripts/test_phase5_file_streaming.py
python3 scripts/test_phase6_reliability.py
```

---

## 🌿 Git Branching & Commit Guidelines

### Branch Naming
* `feat/<feature-name>` for new capabilities
* `fix/<bug-description>` for bug fixes
* `docs/<topic>` for documentation improvements
* `refactor/<module>` for non-breaking code restructuring

### Commit Conventions
We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

* `feat(clipboard): add support for image pasteboard sync`
* `fix(android): resolve BAL exemption for custom in-app copy buttons`
* `docs(readme): update build instructions for macOS 15`
* `perf(file-stream): increase chunk buffer to 128KB for Wi-Fi 6`

---

## 📬 Pull Request Process

1. Fork the repository and create your branch from `main`.
2. Ensure all schema tests and builds succeed.
3. Keep pull requests focused on a single concern.
4. Update the [README.md](README.md) or relevant documentation if introducing user-facing changes.
5. Submit the PR with a clear summary of your changes and any testing notes.

---

## 🛡️ Reporting Security Issues

Please **do not** open public GitHub issues for security vulnerabilities. Instead, refer to [SECURITY.md](SECURITY.md) for our responsible disclosure process.
