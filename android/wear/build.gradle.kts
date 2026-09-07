plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "run.plainstride.wear"
    compileSdk = 36
    compileSdkMinor = 1

    defaultConfig {
        applicationId = "run.plainstride.app.wear"
        minSdk = 30
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }
}

dependencies {
    implementation(project(":core:model"))
    implementation(platform(libs.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.service)
    implementation(libs.compose.ui)
    implementation(libs.wear.compose.material)
    implementation(libs.androidx.health.services)
    implementation(libs.guava.listenablefuture)
    implementation(libs.play.services.wearable)
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.coroutines.play.services)
    implementation(libs.kotlinx.serialization.json)
}
