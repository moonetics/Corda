package com.corda.app.security

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.spec.ECGenParameterSpec
import java.util.Base64

/**
 * Manages local hardware-backed ECDSA P-256 identity keys and SHA-256 fingerprints
 * in the AndroidKeyStore.
 */
object KeyStoreManager {
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val KEY_ALIAS = "com.corda.app.identity_ec_key"

    /**
     * Retrieve existing identity keypair or generate a new hardware-backed ECDSA P-256 keypair.
     */
    fun getOrCreateIdentityKeyPair(): KeyPair {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

        if (keyStore.containsAlias(KEY_ALIAS)) {
            val privateKey = keyStore.getKey(KEY_ALIAS, null) as? java.security.PrivateKey
            val cert = keyStore.getCertificate(KEY_ALIAS)
            if (privateKey != null && cert != null) {
                return KeyPair(cert.publicKey, privateKey)
            }
        }

        // Generate new hardware-backed ECDSA P-256 (secp256r1) keypair
        val keyPairGenerator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC,
            ANDROID_KEYSTORE
        )

        val parameterSpec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
        ).apply {
            setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            setDigests(KeyProperties.DIGEST_SHA256)
        }.build()

        keyPairGenerator.initialize(parameterSpec)
        return keyPairGenerator.generateKeyPair()
    }

    /**
     * Return the Base64 representation of the X.509/DER encoded public key.
     */
    fun getPublicKeyBase64(): String {
        val keyPair = getOrCreateIdentityKeyPair()
        return Base64.getEncoder().encodeToString(keyPair.public.encoded)
    }

    /**
     * Return the standardized SHA-256 fingerprint: XX:XX:XX:...
     */
    fun getPublicKeyFingerprint(): String {
        val keyPair = getOrCreateIdentityKeyPair()
        return calculateFingerprint(keyPair.public.encoded)
    }

    /**
     * Compute SHA-256 colon-delimited hex fingerprint for any public key byte sequence.
     */
    fun calculateFingerprint(rawPublicKey: ByteArray): String {
        val md = MessageDigest.getInstance("SHA-256")
        val digest = md.digest(rawPublicKey)
        return digest.joinToString(":") { "%02X".format(it) }
    }
}
