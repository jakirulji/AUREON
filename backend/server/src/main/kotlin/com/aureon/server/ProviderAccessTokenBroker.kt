package com.aureon.server

import java.util.UUID

/**
 * Isolated credential-broker port. Implementations must load the user's consented
 * provider refresh credential from the encrypted vault, decrypt only inside the
 * broker workload via managed KMS/HSM, refresh with the provider, and expose only
 * a short-lived access token to the supplied operation. Never return refresh tokens.
 */
interface ProviderAccessTokenBroker {
    suspend fun <T> withAccessToken(
        userId: UUID,
        providerAccountId: UUID,
        requiredScopes: Set<String>,
        operation: suspend (String) -> T
    ): T
}

/** Safe default: no provider credentials are available until a reviewed broker is deployed. */
object UnavailableProviderAccessTokenBroker : ProviderAccessTokenBroker {
    override suspend fun <T> withAccessToken(
        userId: UUID,
        providerAccountId: UUID,
        requiredScopes: Set<String>,
        operation: suspend (String) -> T
    ): T {
        throw ProviderCredentialUnavailableException("PROVIDER_CREDENTIAL_BROKER_NOT_CONFIGURED")
    }
}

class ProviderCredentialUnavailableException(val safeCode: String) : RuntimeException(safeCode)
