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
    ":core:assistant",
    ":core:auth",
    ":core:database",
    ":core:data",
    ":core:designsystem",
    ":core:location",
    ":core:media",
    ":core:music",
    ":core:model",
    ":core:network",
    ":core:weather",
    ":feature:onboarding",
    ":feature:activity",
    ":feature:assistant",
    ":feature:progress",
    ":feature:health",
    ":feature:livecoach",
    ":feature:recording",
    ":feature:social",
    ":feature:settings",
    ":feature:today",
    ":wear",
)
