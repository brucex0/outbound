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
        versionCode = 1
        versionName = "1.0"
        buildConfigField("String", "API_BASE_URL", "\"https://api.outbound.run\"")
        buildConfigField("boolean", "DEBUG_IDENTITY_ENABLED", "false")
        val googleServerClientId = providers.gradleProperty("PLAINSTRIDE_GOOGLE_SERVER_CLIENT_ID").orElse("")
        buildConfigField("String", "GOOGLE_SERVER_CLIENT_ID", "\"${googleServerClientId.get()}\"")
        manifestPlaceholders["usesCleartextTraffic"] = "false"
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
        }
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    packaging.resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
}

dependencies {
    implementation(project(":core:analytics"))
    implementation(project(":core:auth"))
    implementation(project(":core:database"))
    implementation(project(":core:designsystem"))
    implementation(project(":core:location"))
    implementation(project(":core:media"))
    implementation(project(":core:model"))
    implementation(project(":core:network"))
    implementation(project(":feature:onboarding"))

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
    debugImplementation(libs.compose.ui.tooling)
}
