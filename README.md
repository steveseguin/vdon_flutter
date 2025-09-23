# VDO.Ninja Flutter Capture

VDO.Ninja's companion Flutter app for publishing camera, microphone, or screen feeds from Android and iOS devices to VDO.Ninja collections or custom self-hosted domains. Mobile is the only supported target; other Flutter platforms may compile but are not tested or maintained.

## Features
- Share camera and microphone feeds to VDO.Ninja on Android and iOS.
- Screen-share on Android with optional mic capture.
- Background operation for long-running captures (subject to each device's battery optimisations).
- Supports custom VDO.Ninja-compatible domains by replacing the default endpoint.

## Current Limitations
- Group rooms are not yet supported.
- Encrypted (&password) connections are not available; use `&password=false` on viewers.
- iOS does not provide screen-share today.
- No UVC / external camera support, and some device cameras may remain incompatible.
- Not feature-complete with the web version of VDO.Ninja.

## Requirements
- Flutter SDK 3.22 or newer (tested with Flutter 3.33.0-1.0.pre.476).
- Dart 3 toolchain bundled with the chosen Flutter release.
- macOS 13+ with Xcode 15+ for iOS development/signing.
- Android Studio (or command-line Android SDK), including:
  - Android SDK Platform 36 and Build-Tools 36.0.0.
  - Java 17 toolchain (bundled with current Android Studio releases).
- Optional: a physical device connected via USB for deployment (`flutter run`).

> **Note:** The Android build uses Android Gradle Plugin 8.6.0 and Kotlin 2.2.0. When updating Flutter or plugins, keep these minimums in sync.

## Getting Started
```bash
git clone https://github.com/steveseguin/vdon_flutter.git
cd vdon_flutter
flutter pub get
```

To verify your environment, run:
```bash
flutter doctor
```
Resolve any reported issues before building.

## Running the App
### Android (debug)
```bash
flutter run -d android
```
Ensure USB debugging is enabled on the device or use an emulator running API level 33+.

### iOS (debug)
```bash
flutter run -d ios
```
On macOS, you can alternatively open `ios/Runner.xcworkspace` in Xcode, select a real device, and press *Run*. iOS simulators are convenient for UI work but do not expose full camera/microphone capabilities.

## Building for Release
### Android APK
```bash
flutter build apk
```
By default the release build falls back to the debug signing configuration if `android/key.properties` is missing. To produce a production-signed APK:
1. Create or locate your keystore (`keystore.jks`).
2. Add `android/key.properties` with:
   ```properties
   storeFile=/absolute/path/to/keystore.jks
   storePassword=...
   keyAlias=...
   keyPassword=...
   ```
3. Re-run `flutter build apk`.
4. The artifact is written to `build/app/outputs/flutter-apk/app-release.apk`.

### iOS App
1. From macOS, run `flutter build ipa` **or** open the Xcode project under `ios/`.
2. Configure signing & capabilities with your Apple Developer certificate.
3. Use Xcode’s Archive workflow or `flutter build ipa --export-options-plist=<path>` to generate an `.ipa`.

## Updating Dependencies
- `flutter pub upgrade --major-versions` updates Dart packages.
- Review generated changes in `pubspec.lock` and test both Android and iOS builds afterwards.
- When Flutter SDK updates introduce new Gradle or Kotlin minimums, mirror those versions in `android/settings.gradle` and `android/build.gradle`.

## Distribution
If you ship the app through app stores, keep in mind:
- Android Play Store submissions require a release keystore (not the debug keystore).
- iOS uploads need an Apple Developer account (paid) and a registered bundle identifier.
- TestFlight/TestFairy or local side-loading are recommended for quick validation.

## Contributing
Contributions that enhance mobile capture reliability are welcome. Common focus areas include:
- Improving hardware compatibility (camera / microphone / UVC).
- Implementing encrypted room support and feature parity with the web app.
- Robust background service behaviour on Android and iOS.

To propose changes:
1. Fork the repository.
2. Create a feature branch, make changes, and ensure `flutter analyze` and target builds pass.
3. Submit a pull request with testing notes.

## License
This project is released under the `LICENSE` file included in the repository.
