plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.plainstride.outbound.core.database"
    compileSdk = 36
    compileSdkMinor = 1
    defaultConfig { minSdk = 26 }
}

dependencies {
    api(project(":core:model"))
    api(libs.androidx.datastore.preferences)
    api(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)
}

ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
    arg("room.generateKotlin", "true")
}
