plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
}

android {
    namespace = "run.plainstride.feature.livecoach"
    compileSdk = 36
    compileSdkMinor = 1
    defaultConfig { minSdk = 26 }
}

dependencies {
    implementation(project(":core:analytics"))
    implementation(project(":core:network"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)
    implementation(libs.retrofit.core)
    implementation(libs.retrofit.kotlinx.serialization)
}
