# CourseVault (mobile)

A local-first course library for Android and iPhone, built with Flutter.

Paste a Mega folder link and it builds your catalogue, tracks progress, and
resumes where you left off. **No accounts, no cloud, no AI.**

## What it does (v1)

- **Course catalogue** — courses > modules > lessons, built by reading a
  Mega folder link. Files are grouped by filename stem: a video (`.mp4`,
  `.mkv`, `.webm`, `.mov`) plus its notes (`.md`, `.txt`), subtitles
  (`.srt`, `.vtt`) and resource files (`.pdf`, `.docx`, …) become one
  lesson. Flat layouts work too: videos directly in a course folder, or
  directly in the linked folder, are accepted.
- **Video player** — streams the lesson video from Mega, resumes where you
  left off, tracks per-lesson and per-course progress (done at ≥ 90%).
- **Subtitles** — `.srt` / `.vtt` files next to a video are shown in the
  player when present.
- **Lesson notes** — `.md` / `.txt` notes rendered in the lesson view.
- **Resources** — other files download to the phone cache and open in the
  system viewer.
- **Search** — across lesson titles, notes and subtitle text.

## How Mega streaming works

Mega stores files AES-CTR encrypted. The app talks to the public Mega JSON
API (`g.api.mega.co.nz/cs`) directly — no Mega account, no third-party
service:

1. `f` lists the folder tree; node keys are AES-ECB decrypted with the
   folder key from the link, attributes are AES-CBC decrypted (zero IV).
2. `g` gets a download URL for a file; byte ranges are fetched as
   `url/start-end` and AES-CTR decrypted.
3. For video, a tiny local HTTP server (`lib/mega/proxy.dart`) serves the
   decrypted bytes to the platform player with `206 Partial Content`, so
   seeking works and the whole file is never held in memory or on disk.

The protocol port is in `lib/mega/` (`crypto.dart`, `api.dart`,
`catalogue.dart`, `proxy.dart`, `download.dart`), following the megajs
reference implementation (qgustavor/mega, MIT).

## Run it

```bash
flutter pub get
flutter run            # Android emulator / connected device
flutter run -d chrome  # web, for UI checks only (video proxy needs a device)
```

## Build the Android APK

```bash
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

The release APK is signed with a keystore that lives in
`android/app/coursevault-release.keystore` (not committed to git) and is
configured in `android/key.properties` (also not committed). Keep that
keystore safe — future updates must be signed with the same one.

Two files are deliberately NOT in git (the push tool only accepts UTF-8
text): the release keystore above, and
`android/gradle/wrapper/gradle-wrapper.jar`. To restore the wrapper jar
after cloning, run `gradle wrapper --gradle-version 8.12` with a local
Gradle install, or download the jar from the Gradle distribution.
The app icon is a vector drawable (`res/drawable/ic_launcher.xml`) and
the iOS icon set is empty on purpose, so the repo contains no PNGs;
add real icons with `flutter_launcher_icons` if you want branded ones.

## Build for iPhone

An `.ipa` cannot be built on Linux — it needs Xcode on a Mac:

```bash
flutter build ipa --release
```

The iOS project (`ios/`) is fully configured (bundle id
`com.coursevault.app`, display name `CourseVault`); build it on a Mac or
with a CI service that has macOS runners.

## Tests

```bash
flutter test                              # unit tests (crypto, links, catalogue)
flutter test test/mega_integration_test.dart   # real Mega link: listing + MP4 decrypt
flutter analyze
```

## Project layout

```
lib/
  main.dart            app entry, dark theme, loads last Mega link on start
  mega/
    link.dart          Mega folder link parsing
    api.dart           Mega JSON API client (+ hashcash)
    crypto.dart        AES ECB/CBC/CTR, key unmerge, attribute decrypt
    catalogue.dart     tree building + course/module/lesson grouping
    proxy.dart         local HTTP server streaming decrypted video ranges
    download.dart      whole-file download + decrypt (notes/resources)
  store/
    library.dart       app state: courses, search index, proxy
    progress_store.dart per-lesson positions/completion (SharedPreferences)
  ui/
    library_screen.dart  Mega link box + course list
    course_screen.dart   modules + lessons
    lesson_screen.dart   video player, notes, resources
    search_screen.dart   search across titles/notes/subtitles
test/
  mega_crypto_test.dart      AES vectors generated with Node crypto
  mega_link_test.dart        link parsing
  catalogue_test.dart        grouping rules incl. flat layouts
  mega_integration_test.dart real Mega link end to end (needs network)
```
