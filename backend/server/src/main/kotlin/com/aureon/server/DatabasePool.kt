package com.aureon.server

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import java.sql.SQLException

data class DatabasePoolSettings(
    val jdbcUrl: String,
    val username: String,
    val password: String,
    val maximumPoolSize: Int = 4
)

/**
 * Small bounded JDBC pool for the control-plane spike.
 * Production deployment still needs reviewed TLS, secret-manager, timeout,
 * metrics and lifecycle configuration.
 */
class DatabasePool(settings: DatabasePoolSettings) : AutoCloseable {
    private val dataSource = HikariDataSource(
        HikariConfig().apply {
            jdbcUrl = settings.jdbcUrl
            username = settings.username
            password = settings.password
            maximumPoolSize = settings.maximumPoolSize.coerceIn(1, 10)
            connectionTimeout = 3_000
            validationTimeout = 1_000
            poolName = "aureon-control-plane"
            isAutoCommit = true
        }
    )

    fun isReady(): Boolean = try {
        dataSource.connection.use { connection ->
            connection.createStatement().use { statement ->
                statement.execute("SELECT 1")
            }
        }
    } catch (_: SQLException) {
        false
    }

    fun <T> withConnection(block: (java.sql.Connection) -> T): T =
        dataSource.connection.use(block)

    override fun close() = dataSource.close()
}
