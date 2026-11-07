package com.aureon.server

/**
 * The spike deliberately ships with a deny-all authenticator.
 *
 * A production implementation must validate a server-issued, revocable AUREON
 * session, bind it to a registered device and enforce token expiry/audience.
 * Do not replace this with a hard-coded token or a client-supplied user ID.
 */
data class AuthenticatedSession(val userId: String)

fun interface SessionAuthenticator {
    suspend fun authenticate(bearerToken: String): AuthenticatedSession?
}

object RejectAllSessionAuthenticator : SessionAuthenticator {
    override suspend fun authenticate(bearerToken: String): AuthenticatedSession? = null
}
