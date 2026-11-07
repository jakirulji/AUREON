package com.aureon.server

import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.auth.Authentication
import io.ktor.server.auth.UserIdPrincipal
import io.ktor.server.auth.authenticate
import io.ktor.server.auth.bearer
import io.ktor.server.auth.principal
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.response.respond
import io.ktor.server.routing.get
import io.ktor.server.routing.routing
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class HealthResponse(val status: String)

@Serializable
data class SessionResponse(val authenticated: Boolean, val userId: String)

fun Application.module(
    sessionAuthenticator: SessionAuthenticator = RejectAllSessionAuthenticator,
    readinessProbe: ReadinessProbe = NotReadyProbe,
    trashRepository: TrashRepository? = null
) {
    install(ContentNegotiation) {
        json(Json {
            ignoreUnknownKeys = false
            encodeDefaults = true
            explicitNulls = false
        })
    }

    install(Authentication) {
        bearer("aureon-session") {
            realm = "AUREON"
            authenticate { credentials ->
                sessionAuthenticator.authenticate(credentials.token)
                    ?.let { UserIdPrincipal(it.userId) }
            }
        }
    }

    routing {
        get("/health/live") { call.respond(HttpStatusCode.OK, HealthResponse("alive")) }
        get("/health/ready") {
            if (readinessProbe.isReady()) call.respond(HttpStatusCode.OK, HealthResponse("ready"))
            else call.respond(HttpStatusCode.ServiceUnavailable, HealthResponse("not_ready"))
        }

        authenticate("aureon-session") {
            get("/v1/me") {
                val principal = call.principal<UserIdPrincipal>()
                if (principal == null) call.respond(HttpStatusCode.Unauthorized, HealthResponse("unauthorized"))
                else call.respond(HttpStatusCode.OK, SessionResponse(true, principal.name))
            }
            if (trashRepository != null) {
                configureTrashRoutes(trashRepository)
            }
        }
    }
}
