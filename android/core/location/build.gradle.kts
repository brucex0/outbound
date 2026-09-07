plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "run.plainstride.core.location"
    compileSdk = 36
    compileSdkMinor = 1
    defaultConfig { minSdk = 26 }
}
