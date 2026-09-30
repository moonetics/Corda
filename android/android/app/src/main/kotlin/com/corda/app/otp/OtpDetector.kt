package com.corda.app.otp

import android.util.Log

data class OtpMatch(
    val code: String,
    val serviceName: String,
    val expiresIn: Int = 60
)

/**
 * Context-aware Privacy-First OTP Sniffer.
 * Extracts 4-8 digit verification codes and sender names while guaranteeing
 * that raw message bodies are never retained or transmitted.
 */
object OtpDetector {
    private const val TAG = "OtpDetector"

    // Numeric code matching: 4, 6, or 8 digits with word boundary
    private val CODE_REGEX = Regex("""\b(?:\d{4}|\d{6}|\d{8})\b""")

    // Contextual keywords confirming this is an authentication/verification message
    private val KEYWORD_REGEX = Regex("""(?i)(?:otp|kode|code|verification|verifikasi|pin|login|rahasia|security|keamanan|one-time|autentikasi|auth)""")

    // Negative filters (ignore tracking numbers, dates, version numbers)
    private val NEGATIVE_REGEX = Regex("""(?i)(?:resi|tracking|awb|inv|order|pesanan|rp|idr|\b202\d\b)""")

    // In-memory deduplication cache: Code -> Timestamp
    private val recentCodes = mutableMapOf<String, Long>()
    private const val DEDUPLICATION_TTL_MS = 60000L // 60 seconds

    /**
     * Inspect notification text and source package.
     * Returns OtpMatch if a valid OTP code and context is detected, null otherwise.
     */
    fun detectOtp(text: String?, title: String?, packageName: String): OtpMatch? {
        if (text.isNullOrBlank()) return null

        val fullText = if (!title.isNullOrBlank()) "$title: $text" else text

        // 1. Verify contextual authentication keyword exists
        if (!KEYWORD_REGEX.containsMatchIn(fullText)) {
            return null
        }

        // 2. Check if it's an order or tracking number false positive
        if (NEGATIVE_REGEX.containsMatchIn(fullText) && !fullText.contains("otp", ignoreCase = true) && !fullText.contains("verifikasi", ignoreCase = true)) {
            return null
        }

        // 3. Extract numeric code candidates
        val matches = CODE_REGEX.findAll(fullText).map { it.value }.toList()
        if (matches.isEmpty()) return null

        // Pick the most likely candidate (prioritize 6-digit standard)
        val code = matches.firstOrNull { it.length == 6 } ?: matches.first()

        // 4. Check deduplication cache
        val now = System.currentTimeMillis()
        cleanExpiredCodes(now)

        if (recentCodes.containsKey(code)) {
            Log.d(TAG, "OTP [$code] sudah diproses sebelumnya dalam 60s. Mengabaikan duplikasi.")
            return null
        }
        recentCodes[code] = now

        // 5. Resolve human-readable service / sender name
        val serviceName = resolveServiceName(title, packageName)

        Log.i(TAG, "🔑 Smart OTP Terdeteksi: [$code] dari '$serviceName' (Sumber: $packageName)")

        return OtpMatch(
            code = code,
            serviceName = serviceName,
            expiresIn = 60
        )
    }

    private fun resolveServiceName(title: String?, packageName: String): String {
        if (!title.isNullOrBlank() && title.length in 2..32 && !title.contains("message", ignoreCase = true)) {
            return title.trim()
        }

        return when {
            packageName.contains("whatsapp") -> "WhatsApp"
            packageName.contains("telegram") -> "Telegram"
            packageName.contains("samsung.android.messaging") -> "Samsung Messages"
            packageName.contains("google.android.apps.messaging") -> "Google Messages"
            packageName.contains("signal") -> "Signal"
            else -> "SMS Verification"
        }
    }

    private fun cleanExpiredCodes(now: Long) {
        val iterator = recentCodes.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            if (now - entry.value > DEDUPLICATION_TTL_MS) {
                iterator.remove()
            }
        }
    }
}
