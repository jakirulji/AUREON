package com.aureon.server

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue

class DatabaseIntegrationTest {
    @Test
    fun postgres18ConnectionSeesV001AndV002SchemaWhenConfigured() {
        val jdbcUrl = System.getenv("AUREON_TEST_DATABASE_URL")
        assumeTrue(!jdbcUrl.isNullOrBlank(), "PostgreSQL integration is enabled in GitHub Actions")
        val username = System.getenv("AUREON_TEST_DATABASE_USER") ?: "aureon"
        val password = System.getenv("AUREON_TEST_DATABASE_PASSWORD") ?: ""

        DatabasePool(
            DatabasePoolSettings(
                jdbcUrl = jdbcUrl!!,
                username = username,
                password = password,
                maximumPoolSize = 2
            )
        ).use { pool ->
            assertTrue(pool.isReady(), "JDBC pool must connect and execute SELECT 1")
            val tables = pool.withConnection { connection ->
                connection.prepareStatement(
                    """
                    SELECT count(*)
                    FROM information_schema.tables
                    WHERE table_schema = 'public'
                      AND table_name = ANY (?)
                    """.trimIndent()
                ).use { statement ->
                    statement.setArray(
                        1,
                        connection.createArrayOf(
                            "text",
                            arrayOf("provider_oauth_transactions", "provider_inventory_cursors", "provider_items")
                        )
                    )
                    statement.executeQuery().use { result ->
                        result.next()
                        result.getInt(1)
                    }
                }
            }
            assertEquals(3, tables, "V002 inventory tables must exist after migration")
        }
    }
}
