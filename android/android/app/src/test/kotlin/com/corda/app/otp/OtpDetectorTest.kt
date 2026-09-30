package com.corda.app.otp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class OtpDetectorTest {

    @Test
    fun testDetects6DigitBankOtp() {
        val result = OtpDetector.detectOtp(
            text = "JANGAN BERIKAN KEPADA SIAPAPUN! Kode OTP transaksi BCA Anda adalah 492015. Berlaku 5 menit.",
            title = "Bank BCA",
            packageName = "com.google.android.apps.messaging"
        )
        assertNotNull("Harus mendeteksi OTP BCA", result)
        assertEquals("492015", result?.code)
        assertEquals("Bank BCA", result?.serviceName)
        assertEquals(60, result?.expiresIn)
    }

    @Test
    fun testDetects4DigitPin() {
        val result = OtpDetector.detectOtp(
            text = "Gunakan kode PIN login 8392 untuk masuk ke akun.",
            title = null,
            packageName = "com.samsung.android.messaging"
        )
        assertNotNull("Harus mendeteksi PIN 4-digit", result)
        assertEquals("8392", result?.code)
        assertEquals("Samsung Messages", result?.serviceName)
    }

    @Test
    fun testDetects8DigitGoogleCode() {
        val result = OtpDetector.detectOtp(
            text = "G-83920145 is your Google verification code.",
            title = "Google Verification",
            packageName = "com.google.android.apps.messaging"
        )
        assertNotNull("Harus mendeteksi kode 8 digit", result)
        assertEquals("83920145", result?.code)
        assertEquals("Google Verification", result?.serviceName)
    }

    @Test
    fun testIgnoresTrackingNumbersWithoutOtpContext() {
        val result = OtpDetector.detectOtp(
            text = "Pesanan Tokopedia Anda dengan nomor resi JNE 982049 sedang dalam perjalanan.",
            title = "JNE Express",
            packageName = "com.tokopedia.tkpd"
        )
        assertNull("Nomor resi/tracking tanpa konteks OTP wajib diabaikan", result)
    }

    @Test
    fun testIgnoresRegularNumbersWithoutAuthKeywords() {
        val result = OtpDetector.detectOtp(
            text = "Halo bro, tolong transfer ke 492015 ya nanti malam.",
            title = "Budi",
            packageName = "com.whatsapp"
        )
        assertNull("Pesan teks biasa tanpa keyword autentikasi wajib diabaikan", result)
    }

    @Test
    fun testDeduplicationCachePreventsRepeatedBroadcasts() {
        val text = "Kode OTP akun Anda adalah 192834."
        val first = OtpDetector.detectOtp(text = text, title = "Verification", packageName = "sms")
        assertNotNull("Panggilan pertama harus berhasil", first)

        val duplicate = OtpDetector.detectOtp(text = text, title = "Verification", packageName = "sms")
        assertNull("Panggilan kedua dengan kode yang sama dalam 60s harus diabaikan", duplicate)
    }
}
