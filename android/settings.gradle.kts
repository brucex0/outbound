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
    ":core:data",
    ":core:designsystem",
    ":core:location",
    ":core:media",
    ":core:model",
    ":core:network",
    ":core:weather",
    ":feature:onboarding",
    ":feature:progress",
    ":feature:health",
    ":feature:recording",
    ":feature:settings",
    ":feature:today",
    ":wear",
)
