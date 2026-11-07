package com.aureon.server

fun interface ReadinessProbe {
    fun isReady(): Boolean
}

object NotReadyProbe : ReadinessProbe {
    override fun isReady(): Boolean = false
}

class DatabaseReadinessProbe(private val databasePool: DatabasePool) : ReadinessProbe {
    override fun isReady(): Boolean = databasePool.isReady()
}
