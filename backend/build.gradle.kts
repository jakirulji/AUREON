plugins {
    kotlin("jvm") version "2.4.21" apply false
    kotlin("plugin.serialization") version "2.4.21" apply false
    id("io.ktor.plugin") version "3.6.1" apply false
}

allprojects {
    group = "com.aureon"
    version = "0.1.0-SNAPSHOT"
}
