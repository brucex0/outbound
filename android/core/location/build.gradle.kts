plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "com.plainstride.outbound.core.location"
    compileSdk = 36
    compileSdkMinor = 1
    defaultConfig { minSdk = 26 }
}
