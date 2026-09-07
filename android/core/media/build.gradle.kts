plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "run.plainstride.core.media"
    compileSdk = 36
    compileSdkMinor = 1
    defaultConfig { minSdk = 26 }
}
