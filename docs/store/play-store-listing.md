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

The Play version code is the pubspec build number (`version:
1.0.1+4` → versionCode 4); every upload needs a higher one.

### Uploading from the command line

The Gradle Play Publisher plugin talks to the Android Publisher API
with a service account (invited in Play Console → Users and
permissions with release + store-presence rights). Its JSON key stays
outside the repo; `app/android/play.properties` (gitignored) names it:

```
serviceAccountFile=/path/to/play-service-account.json
track=alpha
```

Then, after `flutter build appbundle --release`:

```
cd app/android && ./gradlew :app:publishReleaseBundle \
  --artifact-dir ../build/app/outputs/bundle/release
```

Releases land as **drafts** on the configured track with the notes
from `app/src/main/play/release-notes/<locale>/default.txt`; rolling
out is done in the Console (or with `--release-status completed`).
Content rating, data safety, target audience and Play App Signing
enrolment remain Console-only.

## Release notes (max 500 characters per language)

### 1.0.1 (versionCode 4)

en-US:

> Reading position no longer jumps when showing or hiding the menus.
> Footnote markers run a–z through the chapter; tapping one lists the
> whole chapter's footnotes. Keyboard paging follows the view you last
> used. Dictionary entries set ragged-right. Optional keep-screen-on.
> Reading plans import from JSON.

de-DE:

> Die Leseposition springt beim Ein- und Ausblenden der Menüs nicht
> mehr. Fußnoten sind kapitelweise a–z gezählt; ein Tipp zeigt alle
> Fußnoten des Kapitels. Tastatur-Blättern folgt der zuletzt benutzten
> Ansicht. Wörterbucheinträge im Flattersatz. Optional Bildschirm
> anlassen. Lesepläne als JSON importierbar.

## New personal accounts

Personal Play Console accounts created after Nov 2023 must run a
closed test with 12+ testers for 14 days before production access —
plan the timeline accordingly, or use an organization account.
