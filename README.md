# DentPal Mobile App

DentPal is a Flutter mobile app for Android and iOS.

DentPal is an e-commerce application designed for the dental industry. 

The app will initially launch as a single-vendor platform, with plans to evolve into a multi-vendor marketplace in future updates.

## Requirements

- Flutter SDK ^3.9.0
- Dart SDK ^3.9.0
- Android: Minimum SDK 24
- iOS: Minimum version 16.0
- For iOS development: Xcode 14.0 or higher
- For Android development: Java JDK 17 or higher, Android Studio (optional but recommended)

## Development Environment Setup

### 1. Install Homebrew (macOS only)

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2. Install Flutter and Dart

#### macOS
```sh
# Install with Homebrew
brew install --cask flutter

# Verify installation
flutter doctor
```

#### Windows
1. Download Flutter SDK from [flutter.dev](https://docs.flutter.dev/get-started/install/windows)
2. Extract the zip file to a desired location (e.g., `C:\src\flutter`)
3. Add Flutter to your PATH
4. Run `flutter doctor` to verify installation

### 3. Install Java JDK

#### macOS
```sh
brew install openjdk@17

# Add to your shell profile (~/.zshrc or ~/.bash_profile)
echo 'export JAVA_HOME=$(/usr/libexec/java_home)' >> ~/.zshrc
source ~/.zshrc
```

#### Windows
1. Download JDK 17 from [Oracle](https://www.oracle.com/java/technologies/javase-jdk17-downloads.html) or [Adoptium](https://adoptium.net/temurin/releases/?version=17)
2. Run the installer
3. Set JAVA_HOME environment variable

### 4. Install Android Studio and Set Up Android SDK

#### macOS
```sh
brew install --cask android-studio
```

#### Windows
1. Download from [developer.android.com](https://developer.android.com/studio)
2. Run the installer

#### Configure Android SDK (Both platforms)
1. Open Android Studio
2. Go to Tools > SDK Manager
3. In "SDK Platforms", select:
   - Android 14 (API Level 34) or higher
   - Android 13 (API Level 33)
   - Android 12L (API Level 32)
   - Android 12 (API Level 31)
   - Android 11 (API Level 30)
4. In "SDK Tools", select:
   - Android SDK Build-Tools
   - Android SDK Command-line Tools
   - Android Emulator
   - Android SDK Platform-Tools
5. Click "Apply" and follow the prompts to install

#### Set up Android Emulator
1. In Android Studio, go to Tools > Device Manager
2. Click "Create Device"
3. Select a device (e.g., Pixel 5) and click "Next"
4. Select a system image with API Level 30 or higher
5. Click "Finish"

### 5. Install Xcode and iOS Tools (macOS only, required for iOS development)

1. Download Xcode from the Mac App Store
2. Install the Xcode command-line tools:
   ```sh
   xcode-select --install
   ```
3. Accept the license agreement:
   ```sh
   sudo xcodebuild -license accept
   ```
4. Install CocoaPods (required for iOS dependencies):
   ```sh
   sudo gem install cocoapods
   # OR with Homebrew (recommended)
   brew install cocoapods
   ```

#### Set up iOS Simulator or Physical Device
1. For Simulator:
   - Open Xcode
   - Go to Xcode > Open Developer Tool > Simulator
   - In Simulator, go to File > Open Simulator > iOS [version] > [device model]
   
   > **Note:** Remember that Google ML Kit doesn't work on Apple Silicon (M1-M4) simulators
   
2. For Physical Device:
   - Connect your iOS device via USB
   - Open Xcode > Window > Devices and Simulators
   - Select your device and ensure it's recognized
   - On your iOS device, go to Settings > General > Device Management
   - Trust your developer certificate

## Getting Started

To run the app on your device or emulator:

1. Make sure you have Flutter installed. See [Flutter installation guide](https://docs.flutter.dev/get-started/install)
2. Clear all caches:

   ```sh
   # Clean Flutter cache
   flutter clean
   
   # Remove Dart and pub cache (optional but recommended)
   rm -rf .dart_tool/
   rm -rf .pub-cache/
   rm -rf build/
   
   # For iOS
   cd ios && rm -rf Pods Podfile.lock
   cd ..
   
   # For Android
   cd android && ./gradlew clean
   cd ..
   ```

3. Get dependencies:

   ```sh
   flutter pub get
   cd ios && pod install && cd ..
   ```

4. Run the app:

   ```sh
   flutter devices
   flutter run -d "deviceName"
   ```

This will launch the app on the connected device or emulator. 

> **Note:** Clearing the cache is important after pulling new changes, especially when dependencies like Google ML Kit or image_picker have been updated, to avoid build errors from previous cached configurations.

## Project Structure

- `lib/main.dart`: Main entry point of the app
- `pubspec.yaml`: Project configuration and dependencies

## Dependencies

- flutter
- cupertino_icons ^1.0.8
- firebase_core ^4.0.0
- firebase_auth ^6.0.1
- cloud_firestore ^6.0.0
- google_mlkit_text_recognition ^0.15.0
- image_picker ^1.2.0

## Assets
- App icon: `lib/assets/dentpal_vertical.png`
- Fonts:
  - Poppins (`lib/assets/fonts/Poppins-Regular.ttf`)
  - Roboto Black (`lib/assets/fonts/Roboto-Black.ttf`)

## Notes

- This project uses [Firebase](https://firebase.google.com/) for authentication and cloud storage.
- This project also uses [google_mlkit_text_recognition] for
ID verification and OCR.
- This project will 
- The app uses custom fonts and assets as specified in `pubspec.yaml`.
- Not published to pub.dev (`publish_to: none`).
- **Important:** This project **cannot run on Apple Silicon (M1-M4) simulators** because Google ML Kit does not currently support them. You must use a **physical device** for testing on iOS.
- This limitation does **not** affect Android emulators — they will work normally.

- **Firebase setup required:**  
  - Download your `GoogleService-Info.plist` from the Firebase Console and place it in the `ios/Runner` folder.
  - Download your `google-services.json` from the Firebase Console and place it in the `android/app` folder.

For more details, see the [Flutter documentation](https://docs.flutter.dev/).

## Troubleshooting

### Common Issues

1. **Flutter doctor shows errors**
   - Run `flutter doctor -v` for detailed information
   - Follow the instructions provided to resolve each issue

2. **iOS build fails with CocoaPods errors**
   - Ensure CocoaPods is properly installed: `pod --version`
   - Try reinstalling pods: `cd ios && pod deintegrate && pod setup && pod install`
   - For M1/M2/M3/M4 Macs: `arch -x86_64 pod install`

3. **Android build fails**
   - Ensure your Java version is correct: `java -version`
   - Check that JAVA_HOME is set properly: `echo $JAVA_HOME`
   - Verify Gradle can find your Java installation
   - Try running `cd android && ./gradlew clean`

4. **Google ML Kit Issues**
   - Remember that ML Kit text recognition doesn't work on iOS simulators on Apple Silicon
   - Ensure you're testing on physical devices for iOS ML Kit functionality
   - If you get "PlatformException", verify you've added proper permissions:
     - Camera permissions in `Info.plist` for iOS
     - Camera permissions in `AndroidManifest.xml` for Android

5. **Image Picker Permissions**
   - iOS: Check `Info.plist` for `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription`
   - Android: Verify `AndroidManifest.xml` has camera and storage permissions
