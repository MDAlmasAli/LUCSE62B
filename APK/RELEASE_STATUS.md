# App release status (what users have vs. what is waiting)

**Rule from the owner: app updates go out in batches, and only when they say so.** Work lands in
the repo and is built locally as often as needed, but no `publish.bat`, no `/release-apk` upload and
no APK handed to anyone until the owner asks for it. (They held the September batch back for a few
days, then asked for it on 2026-09-27; that batch is now out. The next batch went out on
2026-09-30, again on the owner's say-so.)

## What users have right now

- **v1.1.43+59**, published 2026-09-30 — notifications reach the phone again, deadline
  reminders, more of the app works offline, the home-screen widget gone, and a round of
  security work. Optional, not forced (`min_version_code` 35).
- Before that: v1.1.42+58 (in-app LU result fetch, attendance fixes) on 2026-09-27;
  v1.1.41+52 (light mode, Class Routine card) the same day; v1.1.40+51 handed out manually
  after the key change; v1.1.38+49 was the last OLD-key release.

## Built but NOT shipped

- Nothing right now.

## Waiting for the next release

- Nothing yet. Start a fresh list here as new work lands.

## Still to do by hand, outside the app

- **Run `supabase/lock_down_anon_grants.sql`** in the Supabase SQL editor. Until it runs,
  the published anon key can still read and write `attendance_records`, post notifications
  to the whole class, and read every student's date of birth. The site's birthday greeting
  also stays silent until the `birthdays_today()` function in that file exists.
- **Later, once every phone is on v1.1.43 or newer**, revoke the anon grants on
  `fcm_tokens` and `student_retake_enrollments` — the SQL file's last section has the two
  statements and explains why it has to wait.

## Shipped in v1.1.43+59

- **The home-screen widget is gone.** It could not show the truth: its text was built when
  the data was fetched, so it kept naming a class that had already ended until the next
  refresh, and on phones that kill background work it simply went stale with nothing on it
  to say so. Removed with the `home_widget` and `workmanager` dependencies, the provider,
  its layouts, the manifest receiver and the Calendar & Home Widget screen. The app no
  longer wakes every 15 minutes, so it costs less battery.
- Class reminders (15 minutes before a class) were scheduled from inside that widget
  refresh and would have died with it. They now load the routine themselves on launch,
  which covers the seven days they schedule ahead.
- **Deadline reminders.** A classwork deadline now notifies the student a day before and
  again two hours before. They are scheduled on the phone from the Deadlines sheet, so
  they fire without internet, and they follow the existing "Classwork & deadlines"
  notification switch - turning it off cancels the pending ones. Re-armed on launch and
  whenever the Classwork screen loads.
- **More of the app survives being offline.** LU notices and the notification list are now
  kept on disk like the sheet data already was, so they show the last known items instead
  of an empty screen. (Sheets, Drive listings and the home "showing saved data" banner
  were already in place.)
- **Broadcast notifications reach the notification panel again.** The reported fault was
  that a notification appeared inside the app but never on the phone. The in-app list reads
  Supabase and the panel needs a push, so the two can disagree, and they did: the app gave
  up the `all_users` topic *before* subscribing to the per-category ones, all inside one
  try/catch. A single failed call - a network blip during login was enough - left the device
  subscribed to nothing at all, with the fallback already surrendered. Class routine,
  notice, deadline and app-update pushes then reached nobody, while the in-app list carried
  on as if all was well. Each topic is now subscribed independently, and `all_users` is only
  given up once a category has actually taken. (Direct-to-device pushes, such as birthdays,
  were never affected - verified on a real handset.)
- The manifest had no `default_notification_channel_id`, so a push that arrived on a fresh
  install before the first launch was dropped: Android discards a notification aimed at a
  channel that does not exist yet.
- Notification ids were a raw Dart `hashCode`, which is not bounded to the 32 bits Android
  allows. An out-of-range id makes the platform call throw, losing the notification with
  nothing on screen to say why.
- **The app now says when the phone is refusing to show notifications.** It asks Android
  whether notifications are permitted, at app level and for our channel, and puts a card on
  the home screen with a button that asks for the permission or opens the settings page.
  Blocked and working were previously indistinguishable from inside the app, because the
  in-app list keeps working either way.
- Logging out unsubscribes each topic independently, so one failure no longer leaves the
  rest subscribed.

## Shipped in v1.1.42+58

- **Get your result without copy/paste.** LU retired its JSON result endpoint and now
  serves results only from a form behind a Cloudflare Turnstile check, so the app could no
  longer fetch them. Results now offers "Get my result from LU", which opens LU's own page
  inside the app with the student ID and date of birth already filled in. The student ticks
  the verification themselves (we never touch it); once LU renders the result the page is
  read from the DOM and imported automatically, and the form submits itself once Cloudflare
  has issued its token. Opening Results triggers this on its own, at most once every 10
  minutes. The old paste flow stays as a fallback, reachable from the Results app bar.
- **Attendance no longer un-marks a student.** The site's 30-second auto-refresh rebuilt the
  present list from the server and erased a tap made just before the response landed; local
  changes now win for 15 seconds. The app keeps the same guard and retries a failed save once.
- **Attendance is dated by the Bangladesh day**, not UTC, so marks taken between midnight
  and 6am no longer land on the previous date.

## Shipped in v1.1.41+52

- **Light mode.** Profile → Appearance picks Dark / Light / System (default stays Dark, so
  nobody's app changes look unless they ask for it), plus a quick toggle in the home app bar.
  The choice is saved on the phone and `System` follows the OS.
- Home screen: **Class Routine** card added before Classwork (opens `/info/routine`).
- Class routine: a batch/section listed in several routine links comes only from the first link, so
  last semester's rows no longer mix into the new routine (`lib/core/routine_cells.dart`).
- Routine cells typed like `CSE -4116` now parse as code `CSE-4116` (4 repositories).
- Custom courses are tagged with the semester they were added in; older ones stay hidden.

Start a fresh "waiting" list above as new work lands, and bump `version:` in `pubspec.yaml`
before the next publish (the build number must increase or the app sees no update).

(Web-only fixes — cover page "Download PDF" typo, routine merge on the website, and the
offline work below — are live on the site and are not part of the app release. The site and
the Worker both deploy from a push to `main`; the Worker has to be out before an APK that
depends on a new endpoint.)

## Live on the website

- The site says when it is showing saved data: if a request fails, a banner names how old
  the data on screen is instead of silently presenting last week's routine as today's.
  It also offers a reload once the connection is back.
- The service worker pre-caches the core pages, scripts and styles on each deploy, so a
  page nobody opened before still works offline. Cached sheet responses are evicted
  oldest-first when localStorage runs out of room rather than dropping the newest one.

## The key change is behind us

The signing key changed in September 2026, so the first new-key build (v1.1.40+51) had to be handed
out as a manual APK with an "uninstall the old app first" note. That is done — everyone is on the
new key, and `publish.bat` works normally again. Anyone still on an OLD-key build (v1.1.38 or
earlier) cannot install an update and has to uninstall and reinstall once.

Message to send with the APK (adjust the version):

> 📱 **CSE 62B Portal — notun version (<VERSION>)**
>
> Assalamu Alaikum, nicher APK file ta CSE 62B Portal app er notun version. Ei bar app ta **ekbar
> uninstall kore notun kore install** korte hobe. Ekbar-i korte hobe, tarpor theke ager moto update
> app e nijei ashbe.
>
> **Keno?** Computer reset hoye jaoyay amader app er digital sign (security key) haariye giyechilo,
> tai notun key banate hoyeche. Android ek key diye banano app er upor onno key er app boshate dey
> na, tai purono app er upor update kora jabe na.
>
> **Ki korben:** 1) purono CSE 62B Portal app uninstall korun. 2) Ei APK file install korun
> ("Unknown sources" allow korben). 3) Ager moto login korun.
>
> **Data nirapod?** Ha — account, enrolled course, notification shob server e ache. Shudhu phone e
> save kora login abar dite hobe (date of birth o abar chaite pare).
