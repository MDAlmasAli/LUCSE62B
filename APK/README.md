# CSE 62B Portal — Native App (Flutter)

Native Android/iOS rewrite of the CSE 62B web portal. Reuses the **same backend**
as the website (Supabase + Cloudflare Worker), so no backend changes are needed —
the app is just a new, faster client.

## Stack
- **Flutter** (Dart) — single codebase → Android + iOS, near-native speed.
- **Supabase** (`supabase_flutter`) — postgrest, RPC, realtime (anon key, same as web).
- **Cloudflare Worker** — `/lookup`, `/send-otp`, `/verify-otp`, `/set-password`,
  `/result`, `/dob-*` (unchanged).
- **go_router** — navigation. **google_fonts** (Space Grotesk + Inter).
- **flutter_animate** — smooth UI motion. **ota_update** — in-app APK updates.

## Project layout
```
lib/
├── core/        theme, colors, constants, supabase + worker clients, router
├── data/        models + repositories (auth, session, notifications, dob, update)
├── features/    auth, home, notifications, profile, update, common
└── shared/      reusable widgets (glass card, avatar, gradient button, folder card, toast)
```

## Auth flow (mirrors the website exactly)
1. Student ID → Worker `/lookup` (DEMO is special-cased).
2. `student_has_password` RPC → password path **or** OTP setup path.
3. Password: `verify_student_password` RPC → session saved.
4. OTP: `/send-otp` → `/verify-otp` → `/set-password` for new accounts.
5. **DOB gate** after login: silent verify (device + Supabase fallback), else
   manual entry verified against the LU portal via `/result`.

Session = `{ id, name, loginTime, isDemo }`, persisted in `shared_preferences`
("keep me logged in"); 7-day expiry enforced, demo never persisted.

## In-app updates (forced + changelog)
Driven by the Supabase table **`app_updates`** (latest row = newest build):

| column | meaning |
|---|---|
| `version_name` | display string, e.g. `1.2.0` |
| `version_code` | integer, monotonic — compared to the installed build number |
| `min_version_code` | **forced-update threshold**; installed build below this → app blocked |
| `apk_url` | direct `.apk` download URL (where the new build is hosted) |
| `features` | JSON array → "What's New" list on the update screen |
| `fixes` | JSON array → "Bug Fixes" list |

**To publish a new release:**
1. Bump `version: 1.x.0+N` in `pubspec.yaml` (the `+N` is the version code).
2. `flutter build apk --release` → upload the APK to your host → get its URL.
3. Insert a row into `app_updates` with the new `version_code = N`, `apk_url`,
   `features`, `fixes`.
4. To **force** everyone to update, set `min_version_code = N` (old builds are
   then blocked behind a non-dismissible update screen showing the changelog).

The app checks this table on every launch. Optional updates show a skippable
prompt; forced updates block the whole app until installed.

## Roadmap
- **Phase 1 (done):** project + theme, login/OTP/DOB, home grid, notifications,
  forced in-app update system.
- **Phase 2:** Info hub (routine, exam, bus, teachers, retake), Profile, Students.
- **Phase 3:** Results + analytics, Cover Page PDF, Resources, Gallery.
- **Phase 4:** Games (Imposter, Draw), Attendance, push (FCM).

## Open items (need decisions / assets)
- **APK hosting** for `apk_url` (Cloudflare R2 / GitHub Releases / Drive).
- **Push notifications** → needs a Firebase project + `google-services.json` (FCM).
- **App package id** is currently `com.lucse62b.lucse62b` (permanent once published).
- **iOS** build/publish needs a Mac + Apple Developer account.
