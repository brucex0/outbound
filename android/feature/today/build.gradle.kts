plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
}

android {
    namespace = "run.plainstride.feature.today"
    compileSdk = 36
    compileSdkMinor = 1
    defaultConfig { minSdk = 26 }
    buildFeatures { compose = true }
}

dependencies {
    api(project(":core:model"))
    implementation(project(":core:analytics"))
    implementation(project(":core:database"))
    implementation(project(":core:designsystem"))
    implementation(project(":core:network"))
    implementation(project(":core:weather"))
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.material3)
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(libs.hilt.android)
    implementation(libs.androidx.hilt.navigation.compose)
    ksp(libs.hilt.compiler)
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)
}
