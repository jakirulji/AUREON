package com.aureon.server

import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.server.testing.testApplication
import kotlin.test.Test
import kotlin.test.assertEquals

class ApplicationTest {
    @Test
    fun liveEndpointDoesNotRequireAuthentication() = testApplication {
        application { module() }

        val response = client.get("/health/live")
        assertEquals(HttpStatusCode.OK, response.status)
    }

    @Test
    fun readinessEndpointFailsClosedWithoutDatabase() = testApplication {
        application { module() }

        val response = client.get("/health/ready")
        assertEquals(HttpStatusCode.ServiceUnavailable, response.status)
    }

    @Test
    fun readinessEndpointUsesInjectedProbe() = testApplication {
        application { module(readinessProbe = ReadinessProbe { true }) }

        val response = client.get("/health/ready")
        assertEquals(HttpStatusCode.OK, response.status)
    }

    @Test
    fun protectedEndpointRejectsMissingCredentials() = testApplication {
        application { module() }

        val response = client.get("/v1/me")
        assertEquals(HttpStatusCode.Unauthorized, response.status)
    }

    @Test
    fun protectedEndpointUsesInjectedSessionAuthenticator() = testApplication {
        application {
            module(
                SessionAuthenticator { token ->
                    if (token == "test-only-session") AuthenticatedSession("test-user")
                    else null
                }
            )
        }

        val response = client.get("/v1/me") {
            header(HttpHeaders.Authorization, "Bearer test-only-session")
        }
        assertEquals(HttpStatusCode.OK, response.status)
    }

    @Test
    fun protectedEndpointRejectsInvalidCredentials() = testApplication {
        application {
            module(
                SessionAuthenticator { null }
            )
        }

        val response = client.get("/v1/me") {
            header(HttpHeaders.Authorization, "Bearer invalid")
        }
        assertEquals(HttpStatusCode.Unauthorized, response.status)
    }
}


    @Test
    fun authenticatedProviderTrashRouteUsesUserScopedRepository() = testApplication {
        val expectedUser = java.util.UUID.fromString("00000000-0000-4000-8000-000000000099")
        var requestedUser: java.util.UUID? = null
        val repository = object : TrashRepository {
            override fun list(userId: java.util.UUID, limit: Int, before: java.time.Instant?): List<TrashItemResponse> {
                requestedUser = userId
                return emptyList()
            }
            override fun record(userId: java.util.UUID, request: TrashCreateRequest): TrashItemResponse =
                error("not used in list test")
            override fun transition(
                userId: java.util.UUID,
                trashItemId: java.util.UUID,
                request: TrashTransitionRequest,
                targetStatus: String
            ): TrashItemResponse? = error("not used in list test")
        }
        application {
            module(
                sessionAuthenticator = SessionAuthenticator { token ->
                    if (token == "valid-session") AuthenticatedSession(expectedUser.toString()) else null
                },
                trashRepository = repository
            )
        }

        val response = client.get("/v1/trash/items") {
            header(HttpHeaders.Authorization, "Bearer valid-session")
        }
        assertEquals(HttpStatusCode.OK, response.status)
        assertEquals(expectedUser, requestedUser)
    }
