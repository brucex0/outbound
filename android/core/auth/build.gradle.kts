plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "run.plainstride.core.auth"
    compileSdk = 36
    compileSdkMinor = 1
    defaultConfig { minSdk = 26 }
}

dependencies {
    api(project(":core:model"))
    api(project(":core:network"))
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)
}
