# Mobile Setup Guide

## 1. Create a Firebase Project
1. Open the Firebase Console: https://console.firebase.google.com/
2. Click **Add project** and follow the wizard.
3. Enter a project name, agree to the terms, and create the project.
4. Enable Google Analytics if required, or skip it for a simple prototype.

## 2. Register Android and iOS Apps in Firebase

### Android
1. In Firebase Console, open your project.
2. Click **Add app** and choose **Android**.
3. Enter your Android package name (for example, `com.example.nightowlprototype`).
4. Optionally add an app nickname and SHA-1 if you need authentication or dynamic links.
5. Download the generated `google-services.json` file.

### iOS
1. In Firebase Console, click **Add app** and choose **iOS**.
2. Enter your iOS bundle ID (for example, `com.example.nightowlprototype`).
3. Optionally add an app nickname.
4. Download the generated `GoogleService-Info.plist` file.

## 3. Where to Place Firebase Configuration Files

### Android
- Place `google-services.json` in:
  - `android/app/google-services.json`
- Make sure this file is inside the app module folder, not the project root.

### iOS
- Place `GoogleService-Info.plist` in your iOS app folder:
  - `ios/GoogleService-Info.plist`
- In Xcode, add the file to your app target so it is bundled with the app.

## 4. Get a Google Maps API Key
1. Open Google Cloud Console: https://console.cloud.google.com/
2. Select the same project you use for Firebase or create a new one.
3. Go to **APIs & Services** > **Credentials**.
4. Click **Create credentials** > **API key**.
5. Restrict the key immediately:
   - Under **Application restrictions**, choose **Android apps** or **iOS apps**.
   - For Android, add your package name and SHA-1.
   - For iOS, add your bundle identifier.
6. Under **API restrictions**, enable the required APIs:
   - **Maps SDK for Android**
   - **Maps SDK for iOS**
   - Optionally **Places API** if you use place lookup.
7. Copy the API key and keep it safe.

## 5. Where to Add the Maps API Key

### Android
Add the Maps API key to `android/app/src/main/AndroidManifest.xml` inside the `<application>` block:
```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_GOOGLE_MAPS_API_KEY_HERE" />
```

### iOS
Add the Maps API key in two places:
1. `ios/Info.plist` with the `GMSApiKey` key.
2. `ios/AppDelegate.swift` by calling `GMSServices.provideAPIKey(...)` in `application(_:didFinishLaunchingWithOptions:)`.

## 6. Required Android Permissions
Include these permissions in `android/app/src/main/AndroidManifest.xml` above the `<application>` block:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

If your app needs background location access, also add:
```xml
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
```

## 7. Required iOS Permissions
Add these keys to `ios/Info.plist`:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Allow access to your location so the app can show nearby map content.</string>
```

If your app requires background location tracking, also add:
```xml
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Allow access to your location even when the app is in the background.</string>
```

## 8. Notes
- After adding `google-services.json` and `GoogleService-Info.plist`, rebuild the app so the native tooling picks them up.
- For Android, make sure you also apply the Google Services Gradle plugin in `build.gradle` if you are using Firebase.
- For iOS, make sure the `GoogleService-Info.plist` file is included in the app target and that CocoaPods are installed if you are using Firebase SDKs.
- Replace placeholder values such as `YOUR_GOOGLE_MAPS_API_KEY_HERE` with the real API key before releasing the app.

## 9. Firestore Security Rules Deployment
1. Install Firebase CLI if needed:
   - `npm install -g firebase-tools`
2. Authenticate with Firebase:
   - `firebase login`
3. Select the correct Firebase project:
   - `firebase use <project-id>`
4. Place `firestore.rules` at the project root.
5. Deploy the rules:
   - `firebase deploy --only firestore:rules`

If your `firebase.json` is not configured, run `firebase init firestore` and confirm the rules file path is `firestore.rules`.

## 10. Still needed before the app can run
- `google-services.json` for Android in `android/app/`
- `GoogleService-Info.plist` for iOS in `ios/`
- A valid Google Maps API key set in Android and iOS native config
- Firebase project configuration initialized with the same project used by the app
- `flutter pub get` to install the new dependencies added to `pubspec.yaml`
