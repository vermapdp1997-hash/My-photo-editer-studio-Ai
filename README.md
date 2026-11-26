# My Photo Editor AI

A production-quality, offline-first Flutter Android photo editing application with real on-device AI tools, non-destructive editing, 105+ unique filters, collage maker, local SQLite project storage, and optional Google AdMob support.

## Privacy & Offline Guarantee
- **No login or account required**
- **No Firebase, Supabase, or cloud AI APIs**
- **Photos never leave the device**
- Core editing, filters, adjustments, and bundled on-device ML/TFLite models work in **Airplane Mode**.

## On-Device AI Stack
- **Google ML Kit Selfie Segmentation:** Person cutout, Transparent PNG, Background Replacement, Portrait Blur.
- **Google ML Kit Face Detection:** Targeted face-only skin smoothing & retouching.
- **Real-ESRGAN x4v3 (TFLite, BSD-3-Clause):** AI Photo Enhancer & Old Photo Restoration.
- **AOT-GAN (TFLite, MIT):** AI Object Eraser (Inpainting).
- **DDColor (TFLite, Apache-2.0):** AI Black & White Photo Colorization.

## Building via GitHub Actions
The included `.github/workflows/android-build.yml` automatically:
1. Downloads & SHA-256 verifies open-source `.tflite` models into `assets/ai_models/`.
2. Runs `flutter pub get`, `flutter analyze`, and `flutter test`.
3. Builds `app-release.apk` and Play Store `app-release.aab` artifacts.

## Signed Production Release (Google Play Store)
1. Generate an upload keystore locally:

       keytool -genkey -v -keystore release.keystore -alias upload -keyalg RSA -keysize 2048 -validity 10000

2. Convert keystore to Base64 (`base64 -w 0 release.keystore`) and add these GitHub **Repository Secrets** (`Settings -> Secrets and variables -> Actions`):
   - `KEYSTORE_BASE64`
   - `KEY_ALIAS`
   - `KEY_PASSWORD`
   - `STORE_PASSWORD`
3. Replace the test AdMob App ID in `android/app/src/main/AndroidManifest.xml` and test Ad Unit IDs in `lib/services/ads_service/admob_service.dart` with your real AdMob IDs before uploading the `.aab` to Google Play Console.
