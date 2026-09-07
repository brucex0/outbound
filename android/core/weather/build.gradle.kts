plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "run.plainstride.core.weather"
    compileSdk = 36
    compileSdkMinor = 1
    defaultConfig { minSdk = 26 }
}

dependencies {
    api(project(":core:network"))
    implementation(project(":core:analytics"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)
    implementation(libs.play.services.location)
    implementation(libs.retrofit.kotlinx.serialization)
}
