package com.aureon.server

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class OAuthSecurityTest {
    private val security = OAuthSecurity()

    @Test
    fun generatesUrlSafeStateAndPkceVerifier() {
        val state = security.newState()
        val verifier = security.newPkceVerifier()

        assertEquals(43, state.length)
        assertEquals(43, verifier.length)
        assertTrue(state.all { it.isLetterOrDigit() || it in "-_" })
        assertTrue(verifier.all { it.isLetterOrDigit() || it in "-_" })
    }

    @Test
    fun pkceS256MatchesRfc7636TestVector() {
        val verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        assertEquals(
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
            security.pkceS256Challenge(verifier)
        )
    }

    @Test
    fun pkceRejectsNonAsciiVerifierCharacters() {
        val invalidVerifier = "a".repeat(42) + "é"
        kotlin.test.assertFailsWith<IllegalArgumentException> {
            security.pkceS256Challenge(invalidVerifier)
        }
    }

    @Test
    fun stateHashIsBoundToExactValue() {
        val state = security.newState()
        val storedHash = security.hashState(state)

        assertTrue(security.matchesState(state, storedHash))
        assertFalse(security.matchesState("$state-attacker", storedHash))
        assertFalse(security.matchesState(state, byteArrayOf(1, 2, 3)))
    }

    @Test
    fun redirectUriMustExactlyMatchRegisteredValue() {
        val registered = "https://api.example.invalid/oauth/callback/google_drive"
        val allowlist = OAuthRedirectAllowlist(setOf(registered))

        assertTrue(allowlist.permits(registered))
        assertFalse(allowlist.permits("$registered?next=https://attacker.invalid"))
        assertFalse(allowlist.permits("https://attacker.invalid/oauth/callback/google_drive"))
    }
}
