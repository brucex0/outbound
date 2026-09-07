plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
}

android {
    namespace = "run.plainstride.app"
    compileSdk = 36
    compileSdkMinor = 1

    defaultConfig {
        applicationId = "run.plainstride.app"
        minSdk = 26
        targetSdk = 36
        versionCode = providers.environmentVariable("PLAINSTRIDE_VERSION_CODE").orElse("1").get().toInt()
        versionName = providers.environmentVariable("PLAINSTRIDE_VERSION_NAME").orElse("1.0").get()
        buildConfigField("String", "API_BASE_URL", "\"https://api.outbound.run\"")
        buildConfigField("boolean", "DEBUG_IDENTITY_ENABLED", "false")
        val googleServerClientId = providers.gradleProperty("PLAINSTRIDE_GOOGLE_SERVER_CLIENT_ID").orElse("")
        buildConfigField("String", "GOOGLE_SERVER_CLIENT_ID", "\"${googleServerClientId.get()}\"")
        val firebaseApplicationId = providers.gradleProperty("PLAINSTRIDE_FIREBASE_APPLICATION_ID").orElse("")
        val firebaseApiKey = providers.gradleProperty("PLAINSTRIDE_FIREBASE_API_KEY").orElse("")
        val firebaseProjectId = providers.gradleProperty("PLAINSTRIDE_FIREBASE_PROJECT_ID").orElse("")
        buildConfigField("String", "FIREBASE_APPLICATION_ID", "\"${firebaseApplicationId.get()}\"")
        buildConfigField("String", "FIREBASE_API_KEY", "\"${firebaseApiKey.get()}\"")
        buildConfigField("String", "FIREBASE_PROJECT_ID", "\"${firebaseProjectId.get()}\"")
        val spotifyClientId = providers.gradleProperty("PLAINSTRIDE_SPOTIFY_CLIENT_ID").orElse("")
        buildConfigField("String", "SPOTIFY_CLIENT_ID", "\"${spotifyClientId.get()}\"")
        buildConfigField("String", "SPOTIFY_REDIRECT_URI", "\"run.plainstride.app://spotify-callback\"")
        manifestPlaceholders["usesCleartextTraffic"] = "false"
        manifestPlaceholders["appAuthRedirectScheme"] = "run.plainstride.app"
        val mapsApiKey = providers.gradleProperty("PLAINSTRIDE_MAPS_API_KEY").orElse("")
        manifestPlaceholders["mapsApiKey"] = mapsApiKey.get()
    }

    val releaseStoreFile = providers.environmentVariable("PLAINSTRIDE_ANDROID_KEYSTORE_PATH")
    val releaseStorePassword = providers.environmentVariable("PLAINSTRIDE_ANDROID_KEYSTORE_PASSWORD")
    val releaseKeyAlias = providers.environmentVariable("PLAINSTRIDE_ANDROID_KEY_ALIAS")
    val releaseKeyPassword = providers.environmentVariable("PLAINSTRIDE_ANDROID_KEY_PASSWORD")
    val releaseSigningReady = listOf(releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword).all { it.isPresent }
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
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            buildConfigField("String", "API_BASE_URL", "\"http://10.0.2.2:8787\"")
            buildConfigField("boolean", "DEBUG_IDENTITY_ENABLED", "true")
            manifestPlaceholders["usesCleartextTraffic"] = "true"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (releaseSigningReady) signingConfig = signingConfigs.getByName("release")
            isDebuggable = false
            isJniDebuggable = false
        }
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    packaging.resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
}

tasks.register("verifyPlayReleaseConfiguration") {
    group = "verification"
    doLast {
        check(providers.environmentVariable("PLAINSTRIDE_VERSION_CODE").isPresent) { "PLAINSTRIDE_VERSION_CODE is required for Play artifacts." }
        check(providers.environmentVariable("PLAINSTRIDE_VERSION_NAME").isPresent) { "PLAINSTRIDE_VERSION_NAME is required for Play artifacts." }
        check(listOf("PLAINSTRIDE_ANDROID_KEYSTORE_PATH", "PLAINSTRIDE_ANDROID_KEYSTORE_PASSWORD", "PLAINSTRIDE_ANDROID_KEY_ALIAS", "PLAINSTRIDE_ANDROID_KEY_PASSWORD").all { providers.environmentVariable(it).isPresent }) { "All Plainstride Android upload-signing variables are required for Play artifacts." }
        check(providers.gradleProperty("PLAINSTRIDE_MAPS_API_KEY").isPresent) { "PLAINSTRIDE_MAPS_API_KEY is required for Play artifacts." }
    }
}

dependencies {
    implementation(project(":core:analytics"))
    implementation(project(":core:assistant"))
    implementation(project(":core:auth"))
    implementation(project(":core:database"))
    implementation(project(":core:data"))
    implementation(project(":core:designsystem"))
    implementation(project(":core:location"))
    implementation(project(":core:media"))
    implementation(project(":core:music"))
    implementation(project(":core:model"))
    implementation(project(":core:network"))
    implementation(project(":core:weather"))
    implementation(project(":feature:onboarding"))
    implementation(project(":feature:activity"))
    implementation(project(":feature:assistant"))
    implementation(project(":feature:community"))
    implementation(project(":feature:health"))
    implementation(project(":feature:livecoach"))
    implementation(project(":feature:recording"))
    implementation(project(":feature:progress"))
    implementation(project(":feature:social"))
    implementation(project(":feature:safety"))
    implementation(project(":feature:settings"))
    implementation(project(":feature:today"))

    implementation(platform(libs.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.hilt.navigation.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.androidx.credentials)
    implementation(libs.androidx.credentials.play.services.auth)
    implementation(libs.googleid)
    implementation(libs.retrofit.core)
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)
    implementation(libs.play.services.location)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.analytics)
    implementation(libs.firebase.messaging)
    implementation(libs.appauth)
    implementation(libs.androidx.work.runtime)
    implementation(libs.androidx.health.connect)
    implementation(libs.androidx.hilt.work)
    debugImplementation(libs.compose.ui.tooling)
}
