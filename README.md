# fitflexmobile

FitFlex Flutter mobile app for members and trainers.

## Firebase Google sign-in

The app uses Firebase Auth with Google as the pilot sign-in provider. Add the Firebase platform files before running against a real project:

| Platform | File |
|----------|------|
| Android | `android/app/google-services.json` |
| iOS | `ios/Runner/GoogleService-Info.plist` |

Then run:

```bash
flutter pub get
flutter run --dart-define=API_BASE=http://localhost:3000
```

Pass purchases create a pending payment request. The QR code is only shown after FitFlex admin approval.
# fitflex-mobile
