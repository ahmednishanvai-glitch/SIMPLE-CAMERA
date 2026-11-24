# Simple Camera

Flutter Android camera app: live preview, front/rear switching, flash (off/auto/on),
photo capture, save to the gallery (Pictures/SimpleCamera), and a swipeable,
zoomable preview of the photos taken in the current session.

## Build

Requires Flutter 3.44+ (stable), JDK 17 and the Android SDK (API 36).

    flutter pub get
    flutter run                    # debug on a connected device
    flutter build apk --release    # build/app/outputs/flutter-apk/app-release.apk

The release build is signed with the debug key so it installs anywhere. Add your own
signing config in `android/app/build.gradle.kts` before publishing.

## CI

`.github/workflows/build-apk.yml` builds a release APK on every push to `main`
and uploads it as the `app-release-apk` workflow artifact.

## Notes

- `gradlew` and `gradle-wrapper.jar` are not committed (same as the Flutter
  template); the Flutter tool generates them on the first build.
- Versions: camera ^0.12.2, gal ^2.3.3, AGP 8.11.1, Gradle 8.14.1, Kotlin 2.2.20,
  compileSdk/targetSdk 36, minSdk 24.
