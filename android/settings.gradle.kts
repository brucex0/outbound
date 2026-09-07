pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "Plainstride"

include(
    ":app",
    ":core:analytics",
    ":core:auth",
    ":core:database",
    ":core:designsystem",
    ":core:location",
    ":core:media",
    ":core:model",
    ":core:network",
    ":wear",
)
