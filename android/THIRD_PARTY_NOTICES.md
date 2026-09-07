# Third-Party Notices

This inventory is a release-review aid, not a replacement for the license text shipped by each dependency. Confirm the resolved release graph before every Play upload.

| Family | Use | License |
| --- | --- | --- |
| AndroidX, Jetpack Compose, Room, WorkManager, Health Connect, Benchmark | Android UI, persistence, background work, health integration, performance tooling | Apache License 2.0 |
| Kotlin, kotlinx.coroutines, kotlinx.serialization | Language runtime and concurrency/serialization | Apache License 2.0 |
| Dagger and Hilt | Dependency injection | Apache License 2.0 |
| Retrofit, OkHttp | HTTPS API transport | Apache License 2.0 |
| Google Play services Location, Identity, Wearable | Location, authentication, device connection | Google APIs Terms; bundled open-source components retain their notices |
| Firebase Analytics and Messaging | Privacy-reviewed analytics and push delivery when configured | Google Firebase terms; bundled open-source components retain their notices |

Source and license references:

- https://source.android.com/docs/setup/about/licenses
- https://github.com/JetBrains/kotlin/blob/master/license/README.md
- https://github.com/Kotlin/kotlinx.coroutines/blob/master/LICENSE.txt
- https://github.com/google/dagger/blob/master/LICENSE.txt
- https://github.com/square/retrofit/blob/trunk/LICENSE.txt
- https://github.com/square/okhttp/blob/master/LICENSE.txt

Archive `./gradlew :app:dependencies --configuration releaseRuntimeClasspath` with every release and update this file whenever the direct dependency families change.
