plugins { alias(libs.plugins.android.library); alias(libs.plugins.kotlin.compose); alias(libs.plugins.hilt); alias(libs.plugins.ksp) }
android { namespace = "com.plainstride.outbound.feature.assistant"; compileSdk = 36; compileSdkMinor = 1; defaultConfig { minSdk = 26 }; buildFeatures { compose = true } }
dependencies {
    implementation(project(":core:analytics")); implementation(project(":core:assistant")); implementation(project(":core:music"))
    implementation(project(":core:network"))
    implementation(platform(libs.compose.bom)); implementation(libs.compose.material3); implementation(libs.compose.material.icons.extended); implementation(libs.compose.ui)
    implementation(libs.androidx.activity.compose); implementation(libs.androidx.lifecycle.runtime.compose); implementation(libs.androidx.hilt.navigation.compose)
    implementation(libs.hilt.android); ksp(libs.hilt.compiler)
}
