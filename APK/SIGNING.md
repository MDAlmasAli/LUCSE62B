# Android release signing, build & publish

Everything needed to build and ship the CSE 62B Portal APK from a fresh PC or a new
chat. **No secrets are in this file** — the keystore and its password live outside git.

- Application id: `com.lucse62b.portal` (version lives in `pubspec.yaml`, e.g. `1.1.40+51`)
- Release signing is configured in `android/app/build.gradle.kts`. It reads
  `android/key.properties` (gitignored); if that file is missing the build silently falls
  back to the **debug** key — which is fine for a compile check and **wrong for anything you ship**.

## The current signing key (created 2026-09-26)

| | |
|---|---|
| Keystore file | `lucse62b-release.jks` (PKCS12, RSA 2048, valid ~27 years) |
| Alias | `lucse62b` |
| Certificate DN | `CN=CSE 62B Portal, OU=CSE, O=Leading University, L=Sylhet, ST=Sylhet, C=BD` |
| Certificate SHA-256 | `4de19cfc6cf7d55d514c0b9b56ece9e7d1b7ffc8681025fc478a56160efb4d1b` |

Copies (keep at least two, on different devices):
- `APK\android\keystore\lucse62b-release.jks` + `APK\android\key.properties` — the copy the build
  uses (both gitignored, so they are never pushed, but `git clean -fdx` would delete them)
- `D:\Keys\lucse62b\` — backup: `lucse62b-release.jks` + `key.properties`
- `E:\Backup\lucse62b-signing\` — second backup of the same two files
- The owner's own private copy (Google Drive / pendrive / password manager) — **the password is only in `key.properties`**

`git clean -fdx` deletes every gitignored file, which is the most likely reason the previous key
disappeared — so never rely on the in-project copy alone; keep the `D:\Keys` / `E:\Backup` copies.

### `android/key.properties` (create it on every machine; never commit)

```
storePassword=<password>
keyPassword=<same password>
keyAlias=lucse62b
storeFile=../keystore/lucse62b-release.jks
```

`storeFile` is resolved relative to `android/app`, so `../keystore/…` points at
`android/keystore/`. Use forward slashes (backslashes are escapes in `.properties` files).

### The previous key is gone

The key that signed v1.1.32 – v1.1.39 (certificate SHA-256
`dfa3621ea9d2935bd590c98d2f4168de76aca80a17fb68c43f68e2bde3a34504`) was lost when Windows was
reset on 2026-08-04. **Android refuses to update an app signed with a different key**, so anyone
still on a build signed with the old key must **uninstall it and install the new APK once**
(their data lives in Supabase; only the saved login is lost).

## Setting up a new PC

1. **JDK 21** (e.g. Microsoft OpenJDK 21) and **Git**.
2. **Flutter** stable (built with 3.47.5 / Dart 3.13; the app needs Dart ≥ 3.12):
   `git clone --depth 1 -b stable https://github.com/flutter/flutter.git D:\Tools\flutter`
3. **Android SDK** into `D:\Android\Sdk`: download the *command-line tools* zip from
   developer.android.com/studio, unpack to `D:\Android\Sdk\cmdline-tools\latest`, then
   `sdkmanager --sdk_root=D:\Android\Sdk --licenses` and
   `sdkmanager --sdk_root=D:\Android\Sdk platform-tools "platforms;android-36" "build-tools;36.0.0"`.
   (Gradle fetches NDK/CMake on the first build.)
4. Environment: add `D:\Tools\flutter\bin` and `D:\Android\Sdk\platform-tools` to `PATH`;
   set `ANDROID_HOME` and `ANDROID_SDK_ROOT` to `D:\Android\Sdk`; then
   `flutter config --android-sdk D:\Android\Sdk --jdk-dir "<your JDK 21 folder>"` and `flutter doctor`.
5. Copy `lucse62b-release.jks` somewhere permanent, and create `APK\android\key.properties` (above).
6. Build: `cd APK` → `flutter pub get` → `flutter build apk --release`
   (first build ≈ 30 min while Gradle downloads everything; later ones ≈ 1–2 min).
   Output: `APK\build\app\outputs\flutter-apk\app-release.apk`.
7. **Verify the signature before shipping** (must print the SHA-256 in the table above):
   `D:\Android\Sdk\build-tools\36.0.0\apksigner.bat verify --print-certs app-release.apk`

`flutter pub get` may rewrite `pubspec.lock` / `analysis_options.yaml` when the Flutter version
differs; that is noise — `git checkout` those two files instead of committing them.

## Publishing (in-app update)

`APK\publish.bat` builds and uploads the APK to the Worker (`/release-apk`), which writes the
`app_updates` row that every installed app reads.

- It needs `APK\.release-key` — one line containing `RELEASE_PUBLISH_KEY`. That value is a
  **GitHub Actions secret** deployed to the Worker (`.github/workflows/deploy-worker.yml`). If it is
  lost, set a new secret value in GitHub → run the *Deploy Worker* workflow → put the same value in
  `.release-key`.
- Bump `version:` in `pubspec.yaml` (the `+N` build number must increase) and edit the
  `x-release-features` / `x-release-fixes` lists in `publish.bat` for each release.
- **Do not publish an APK signed with a different key than the installed one.** The update is
  *forced*: installed apps download it, the install then fails on the signature mismatch, and users
  are stuck on the update screen. From 2026-09-26 the shipped key is the one above; the very first
  build after the key change must be handed out as a manual download with an "uninstall the old
  app first" note, not pushed through `publish.bat`, until everybody has switched.
