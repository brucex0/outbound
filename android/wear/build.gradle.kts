plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.plainstride.outbound.wear"
    compileSdk = 36
    compileSdkMinor = 1

    defaultConfig {
        applicationId = "com.plainstride.outbound.wear"
        minSdk = 30
        targetSdk = 36
        versionCode = providers.environmentVariable("PLAINSTRIDE_VERSION_CODE").orElse("1").get().toInt()
        versionName = providers.environmentVariable("PLAINSTRIDE_VERSION_NAME").orElse("1.0").get()
    }

    val releaseStoreFile = providers.environmentVariable("PLAINSTRIDE_ANDROID_KEYSTORE_PATH")
    val releaseStorePassword = providers.environmentVariable("PLAINSTRIDE_ANDROID_KEYSTORE_PASSWORD")
    val releaseKeyAlias = providers.environmentVariable("PLAINSTRIDE_ANDROID_KEY_ALIAS")
    val releaseKeyPassword = providers.environmentVariable("PLAINSTRIDE_ANDROID_KEY_PASSWORD")
    val releaseSigningReady = listOf(releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword).all { it.isPresent && it.get().isNotBlank() }
    signingConfigs {
        if (releaseSigningReady) create("release") {
            storeFile = file(releaseStoreFile.get())
            storePassword = releaseStorePassword.get()
            keyAlias = releaseKeyAlias.get()
            keyPassword = releaseKeyPassword.get()
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
            enableV4Signing = true
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            if (releaseSigningReady) signingConfig = signingConfigs.getByName("release")
        }
    }
}

tasks.register("verifyWearPlayReleaseConfiguration") {
    group = "verification"
    doLast {
        val versionCode = providers.environmentVariable("PLAINSTRIDE_VERSION_CODE").orNull?.toIntOrNull()
        check(versionCode != null && versionCode > 0) { "A positive PLAINSTRIDE_VERSION_CODE is required for Wear Play artifacts." }
        check(!providers.environmentVariable("PLAINSTRIDE_VERSION_NAME").orNull.isNullOrBlank()) { "PLAINSTRIDE_VERSION_NAME is required for Wear Play artifacts." }
        check(listOf("PLAINSTRIDE_ANDROID_KEYSTORE_PATH", "PLAINSTRIDE_ANDROID_KEYSTORE_PASSWORD", "PLAINSTRIDE_ANDROID_KEY_ALIAS", "PLAINSTRIDE_ANDROID_KEY_PASSWORD").all { !providers.environmentVariable(it).orNull.isNullOrBlank() }) { "All Plainstride Android upload-signing variables are required for Wear Play artifacts." }
        check(file(providers.environmentVariable("PLAINSTRIDE_ANDROID_KEYSTORE_PATH").get()).isFile) { "PLAINSTRIDE_ANDROID_KEYSTORE_PATH must point to a readable keystore." }
    }
}

tasks.matching { it.name == "bundleRelease" }.configureEach {
    dependsOn("verifyWearPlayReleaseConfiguration")
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
