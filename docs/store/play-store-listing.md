# Play Store listing · gramma

App name (max 30): `gramma — Bible Study`   (20)
Category: Books & Reference. Price: Free. Ads: none. IAP: none.
Privacy policy: https://github.com/sse1234/gramma/blob/main/PRIVACY.md
Data safety form: **No data collected, no data shared** (all answers
No; the optional sync writes to user-chosen storage, end-to-end
encrypted — no developer access).
Content rating questionnaire: all No → Everyone / USK 0.

## Short description (max 80 characters)

- en: `Bible study with book-grade typography. Offline, open source,
  free forever.`   (76)
- de: `Bibelstudium mit Typografie wie im Buch. Offline, quelloffen,
  für immer frei.`   (78)

## Full description

Use the App Store description texts verbatim
(docs/store/app-store-listing.md, en-US and de-DE sections) — Play's
4000-character limit fits them unchanged.

## Graphics

- App icon 512×512: export from the iOS 1024 master, scaled.
- Feature graphic 1024×500: ~/dev/gramma-private/screenshots/play-feature-graphic.png
- Phone screenshots (min 2): the Tab S2 or Android-emulator
  equivalents of the iPhone set; Play accepts flexible sizes
  (16:9–9:16, 320–3840 px).

## Build

Signed AAB: `app/build/app/outputs/bundle/release/app-release.aab`,
upload key `~/dev/gramma-private/upload-keystore.jks` (password in
app/android/key.properties, both device-local — BACK THEM UP).
Enroll in Play App Signing on first upload (Google holds the app
signing key; ours is the upload key).

## New personal accounts

Personal Play Console accounts created after Nov 2023 must run a
closed test with 12+ testers for 14 days before production access —
plan the timeline accordingly, or use an organization account.
