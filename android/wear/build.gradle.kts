plugins {
    alias(libs.plugins.android.application)
}

android {
    namespace = "run.plainstride.wear"
    compileSdk = 36
    compileSdkMinor = 1

    defaultConfig {
        applicationId = "run.plainstride.app.wear"
        minSdk = 30
        targetSdk = 35
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
