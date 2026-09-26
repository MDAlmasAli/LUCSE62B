# App release status (what users have vs. what is waiting)

**Rule from the owner (2026-09-27): do NOT give any app update to users yet.** More changes are
coming first; everything is shipped to everyone's phones together, in one go. Until the owner says
"ship it": no `publish.bat`, no `/release-apk` upload, no APK sent out, no "update available"
row in `app_updates`. Building local APKs for testing is fine. Committing/pushing source is fine.

## What users have right now

- **v1.1.39+50**, signed with the OLD key (lost on 2026-08-04, see `SIGNING.md`).

## Built but NOT shipped

- **v1.1.41+52**, signed with the NEW key — `D:\Releases\lucse62b-v1.1.41-all-phones.apk`
  (47 MB, arm64 + arm32; `flutter build apk --release --target-platform android-arm,android-arm64`).
- v1.1.40+51 was an earlier local build of the same thing, never handed out.

## Changes waiting for the next release (app side)

- Home screen: **Class Routine** card added before Classwork (opens `/info/routine`).
- Class routine: a batch/section listed in several routine links comes only from the first link, so
  last semester's rows no longer mix into the new routine (`lib/core/routine_cells.dart`).
- Routine cells typed like `CSE -4116` now parse as code `CSE-4116` (4 repositories).
- Custom courses are tagged with the semester they were added in; older ones stay hidden.

Add new items here as more work lands; bump `version:` in `pubspec.yaml` only when actually shipping.

(Web-only fixes — cover page "Download PDF" typo, routine merge on the website — are already live
on the site and are not part of the app release.)

## How the first release must go out

The signing key changed, so nobody can update in place. The first new-key build has to be handed
out as a **manual APK (WhatsApp/Telegram/Drive) with an "uninstall the old app first" note**, NOT
through `publish.bat` (the forced in-app update would fail on the signature mismatch and strand
users). After everyone is on the new key, normal `publish.bat` releases work again.

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
