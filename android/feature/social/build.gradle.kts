plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.plainstride.outbound.feature.social"
    compileSdk = 36
    compileSdkMinor = 1
    defaultConfig {
        minSdk = 26
        testInstrumentationRunner = "com.plainstride.outbound.feature.social.ProfileTestRunner"
    }
    buildFeatures { compose = true }
}

dependencies {
    implementation(project(":feature:activity"))
    implementation(project(":core:designsystem"))
    implementation(project(":core:analytics"))
    implementation(project(":core:database"))
    implementation(project(":core:data"))
    implementation(project(":core:model"))
    implementation(project(":core:network"))
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.maps.compose)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.hilt.navigation.compose)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.retrofit.core)
    implementation(libs.retrofit.kotlinx.serialization)
    implementation(libs.okhttp)
    implementation(libs.camerax.camera2)
    implementation(libs.camerax.lifecycle)
    implementation(libs.camerax.view)
    implementation("com.google.zxing:core:3.5.3")
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("com.google.dagger:hilt-android-testing:${libs.versions.hilt.get()}")
    kspAndroidTest(libs.hilt.compiler)
    debugImplementation("androidx.compose.ui:ui-test-manifest")
    debugImplementation(libs.compose.ui.tooling)
}
