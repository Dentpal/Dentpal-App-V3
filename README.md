# DentPal Mobile App

DentPal is a Flutter mobile app for Android and iOS.

DentPal is an e-commerce application designed for the dental industry. 

The app will initially launch as a single-vendor platform, with plans to evolve into a multi-vendor marketplace in future updates.

## Requirements

- Flutter SDK ^3.9.0
- Dart SDK ^3.9.0
- Android: Minimum SDK 24
- iOS: Minimum version 15.0

## Getting Started

To run the app on your device or emulator:

1. Make sure you have Flutter installed. See [Flutter installation guide](https://docs.flutter.dev/get-started/install)
2. In the project directory, run:

   ```sh
   flutter pub get
   flutter run
   ```

This will launch the app on the connected device or emulator.

## Project Structure

- `lib/main.dart`: Main entry point of the app
- `pubspec.yaml`: Project configuration and dependencies

## Dependencies

- flutter
- cupertino_icons ^1.0.8
- firebase_core ^4.0.0
- firebase_auth ^6.0.1
- cloud_firestore ^6.0.0

## Assets
- App icon: `lib/assets/dentpal_vertical.png`
- Fonts:
  - Poppins (`lib/assets/fonts/Poppins-Regular.ttf`)
  - Roboto Black (`lib/assets/fonts/Roboto-Black.ttf`)

## Notes

- This project uses [Firebase](https://firebase.google.com/) for authentication and cloud storage.
- The app uses custom fonts and assets as specified in `pubspec.yaml`.
- Not published to pub.dev (`publish_to: none`).
- **Firebase setup required:**  
  - Download your `GoogleService-Info.plist` from the Firebase Console and place it in the `ios/Runner` folder.
  - Download your `google-services.json` from the Firebase Console and place it in the `android/app` folder.

For more details, see the [Flutter documentation](https://docs.flutter.dev/).
