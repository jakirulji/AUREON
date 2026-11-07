plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

group = "com.aureon.localfiles"
version = "0.1.0"

android {
    namespace = "com.aureon.localfiles"
    compileSdk = 36

    defaultConfig {
        minSdk = 23
    }
}
