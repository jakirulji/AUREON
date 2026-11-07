plugins {
    kotlin("jvm")
    kotlin("plugin.serialization")
    id("io.ktor.plugin")
    application
}

kotlin {
    jvmToolchain(21)
}

application {
    mainClass.set("io.ktor.server.netty.EngineMain")
}

dependencies {
    implementation("io.ktor:ktor-server-core-jvm:3.6.1")
    implementation("io.ktor:ktor-server-netty-jvm:3.6.1")
    implementation("io.ktor:ktor-server-content-negotiation-jvm:3.6.1")
    implementation("io.ktor:ktor-serialization-kotlinx-json-jvm:3.6.1")
    implementation("io.ktor:ktor-server-auth-jvm:3.6.1")
    implementation("ch.qos.logback:logback-classic:1.6.6")
    implementation("com.zaxxer:HikariCP:7.1.0")
    runtimeOnly("org.postgresql:postgresql:42.7.8")
    testImplementation("org.postgresql:postgresql:42.7.8")

    testImplementation("io.ktor:ktor-server-test-host-jvm:3.6.1")
    testImplementation(kotlin("test"))
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit5:2.4.21")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test {
    useJUnitPlatform()
}
