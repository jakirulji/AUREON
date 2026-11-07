package com.aureon.server

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

class OAuthSecurity(private val secureRandom: SecureRandom = SecureRandom()) {
    fun newState(): String = randomUrlSafeValue(32)

    fun newPkceVerifier(): String = randomUrlSafeValue(32)

    fun pkceS256Challenge(verifier: String): String {
        require(verifier.length in 43..128) { "PKCE verifier length is invalid" }
        require(verifier.all { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it in "-._~" }) {
            "PKCE verifier contains invalid characters"
        }
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(verifier.toByteArray(Charsets.US_ASCII))
        return Base64.getUrlEncoder().withoutPadding().encodeToString(digest)
    }

    fun hashState(state: String): ByteArray {
        require(state.isNotBlank())
        return MessageDigest.getInstance("SHA-256").digest(state.toByteArray(Charsets.UTF_8))
    }

    fun matchesState(presentedState: String, expectedSha256: ByteArray): Boolean {
        if (expectedSha256.size != 32 || presentedState.isBlank()) return false
        return MessageDigest.isEqual(hashState(presentedState), expectedSha256)
    }

    private fun randomUrlSafeValue(bytes: Int): String {
        val random = ByteArray(bytes)
        secureRandom.nextBytes(random)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(random)
    }
}

/** Exact-match allowlist. Never accept a callback URL supplied by an untrusted client. */
class OAuthRedirectAllowlist(registeredRedirectUris: Set<String>) {
    private val allowed = registeredRedirectUris.toSet()

    fun permits(candidate: String): Boolean = candidate in allowed
}
