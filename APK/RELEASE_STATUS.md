# App release status (what users have vs. what is waiting)

**Rule from the owner: app updates go out in batches, and only when they say so.** Work lands in
the repo and is built locally as often as needed, but no `publish.bat`, no `/release-apk` upload and
no APK handed to anyone until the owner asks for it. (They held the September batch back for a few
days, then asked for it on 2026-09-27; that batch is now out.)

## What users have right now

- **v1.1.42+58**, published 2026-09-27 — the in-app LU result fetch plus the attendance
  fixes. Optional, not forced (`min_version_code` 35).
- Before that: v1.1.41+52 (light mode, Class Routine card) published the same day;
  v1.1.40+51 handed out manually after the key change; v1.1.38+49 was the last OLD-key release.

## Built but NOT shipped

- Nothing right now.

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

(Web-only fixes — cover page "Download PDF" typo, routine merge on the website — are already live
on the site and are not part of the app release.)

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
