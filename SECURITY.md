# Security Policy

## 🔒 Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

---

## 🛡️ Reporting a Vulnerability

The Corda team takes the security of our users and their data seriously. Because Corda handles clipboard data (including passwords and personal notes) and local file streaming, security is our highest priority.

If you believe you have discovered a vulnerability, please **do not** disclose it publicly via GitHub Issues.

Instead, please send an encrypted or direct email to the project maintainers:
* **Email**: `yudistira.bimo1312@gmail.com`
* **Subject**: `[SECURITY VULNERABILITY] Corda - <Short Description>`

Please include:
1. Detailed steps to reproduce the issue (proof-of-concept scripts or reproduction environment).
2. The affected platform (macOS, Android, or protocol level).
3. The potential impact on user data or device integrity.

You will receive an acknowledgment within 48 hours, followed by regular status updates as we investigate and develop a patch.

---

## 🔐 Cryptographic Architecture & Threat Model

* **Transport Layer Security**: All data in transit across local networks is encrypted using TLS 1.3 or authenticated TCP sockets with pinned peer fingerprints.
* **Mutual Authentication**: Devices verify public keys exchanged during initial pairing. Unrecognized devices cannot inject clipboard data or stream files.
* **Echo Protection**: Bi-directional clipboard loops are prevented using deterministic SHA-256 content hashing.
* **Local Isolation**: Corda makes zero outgoing connections to external servers or cloud services. All communication is strictly confined to the local area network (LAN).
