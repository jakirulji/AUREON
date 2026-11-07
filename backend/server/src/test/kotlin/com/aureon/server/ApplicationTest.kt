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
