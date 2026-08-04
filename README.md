# YGO Scanner

Catalogue a physical Yu-Gi-Oh card collection with your phone camera.

Point the camera at a card, and the app recognises it from its artwork. Confirm
the match, pick a condition, and it is saved to your collection. Everything is
stored on the device in a local database, so the app works offline after the
first setup.

> This is a personal hobby project. It is not affiliated with, endorsed by, or
> connected to Konami. Card data and card images come from the public
> [YGOPRODeck API](https://ygoprodeck.com/api-guide/).

---

## What it does

- **Artwork recognition.** The camera finds the card in the guide box,
  straightens it, and compares its artwork against a bundled index of about
  14,600 card images. You always review and confirm the match before anything
  is saved.
- **Passcode scanning.** An optional mode that reads the 8 digit passcode
  printed in the bottom left corner of a card instead of matching the artwork.
- **Manual search.** Type a card name and add it by hand. This is a permanent,
  first class alternative, not just a fallback for when scanning fails.
- **Your collection.** Browse, search and filter by set, rarity, condition,
  edition, language, level, attack, defence and more. Three view modes, from a
  detailed list down to a dense artwork grid.
- **Per card details.** Condition (Mint through Poor), edition, language, set
  and rarity, and quantity. Editing an entry into a combination you already own
  merges the two automatically instead of creating a duplicate.
- **CSV export and import.** Export the whole collection as a spreadsheet
  friendly CSV, and import one back in with a choice of merge rules.
- **Statistics.** Total copies, distinct cards, and breakdowns by condition,
  language and card type.

---

## Install the finished app (no building required)

If you just want to use the app on an Android phone, you do not need any of the
tools below.

1. Open the **Releases** page of this repository.
2. Download the `.apk` file from the newest release.
3. Open the downloaded file on your phone. Android will ask you to allow
   installing apps from this source. Approve it, then tap Install.
4. The first time you open the app it downloads the card database from
   YGOPRODeck. This needs an internet connection and takes a minute or two.
   After that the app works offline.

There is no iOS download. Apple does not allow installing apps outside the App
Store without a paid developer account, so on iPhone you have to build it
yourself using the steps below.

---

## Building the app yourself

These steps assume you have never used a code editor. Follow them in order.
Anything written `like this` is something you type into a terminal.

### What you need

| | |
|---|---|
| A computer | Windows, macOS or Linux |
| Free disk space | About 15 GB, mostly for the Android tools |
| An internet connection | For the downloads, and for the app's first launch |
| Time | 30 to 60 minutes the first time, a couple of minutes after that |

To build for **iPhone** you additionally need a Mac. There is no way around
this; Apple's build tools only run on macOS.

### Step 1: Install Flutter

Flutter is the toolkit this app is written in.

1. Go to <https://docs.flutter.dev/get-started/install> and pick your operating
   system.
2. Follow that page to the end. It walks you through downloading Flutter and
   adding it to your system PATH, which is what lets you run the `flutter`
   command from anywhere.
3. Open a terminal (on Windows use **PowerShell**, on macOS use **Terminal**)
   and check it worked:

   ```
   flutter --version
   ```

   You should see a version number. This project was built with Flutter 3.44
   and Dart 3.12. Any newer stable version should work.

### Step 2: Install the platform tools

**For Android**, install [Android Studio](https://developer.android.com/studio).
When it first opens, accept the default setup, which installs the Android SDK
and build tools. Then in a terminal run this once to accept the licences:

```
flutter doctor --android-licenses
```

Press `y` at every prompt.

**For iPhone**, install Xcode from the Mac App Store, open it once, and accept
its licence agreement.

### Step 3: Check everything is ready

```
flutter doctor
```

This prints a checklist. Every line you need should have a green tick. Ignore
lines about platforms you do not care about, for example "Chrome" or "Visual
Studio" if you only want an Android build. If something is missing, the command
usually tells you exactly what to run to fix it.

### Step 4: Get the code

If you have Git installed:

```
git clone https://github.com/carlolzz/ygo-card-recognition.git
cd ygo-card-recognition
```

If you do not have Git, use the green **Code** button at the top of the
repository page, choose **Download ZIP**, unzip it, and then in your terminal
move into the unzipped folder using `cd` followed by its path.

### Step 5: Download the project's dependencies

```
flutter pub get
```

### Step 6: Generate the code that is not stored in the repository

Some Dart files are generated automatically from the code rather than being
saved in the repository. You have to create them once before the app will
compile:

```
dart run build_runner build --delete-conflicting-outputs
```

This takes a minute or so. Run it again any time you change a model or a
provider class.

> If you skip this step you will see a long list of errors about missing files
> ending in `.g.dart` or `.freezed.dart`. That list is normal and this command
> is the fix.

### Step 7: Build it

**Android, quick test on a connected phone.** Enable Developer Options and USB
debugging on the phone (search the web for those two terms plus your phone
model), plug it in, then:

```
flutter run
```

**Android, an installable APK file.**

```
flutter build apk --release
```

When it finishes, the file is at:

```
build/app/outputs/flutter-apk/app-release.apk
```

Copy that file to your phone and open it to install.

**Android, smaller APKs per phone type.** The single APK above contains the
code for every processor type, which makes it large. To get smaller files
instead:

```
flutter build apk --split-per-abi
```

This produces three files in the same folder. `app-arm64-v8a-release.apk` is
the one that fits nearly every phone made since about 2016.

**iPhone.** On a Mac, with your phone plugged in and trusted:

```
flutter run
```

Building an `.ipa` you can hand to someone else requires a paid Apple Developer
account and code signing setup, which is outside the scope of this README.

### About signing (Android)

An Android app has to be signed before a phone will install it.

- **You do not need to do anything.** If there is no signing key configured,
  the release build automatically falls back to the debug key, so the commands
  above just work.
- **If you want to sign with your own key**, copy
  `android/key.properties.example` to `android/key.properties` and fill in the
  four values. That file and the keystore it points at are deliberately
  excluded from the repository and must never be committed. The template file
  explains how to create a keystore.

---

## Running the tests

```
flutter test
```

This runs the full suite on your computer, with no phone required. Everything
should pass.

The Python helper tools have their own tests, which run offline:

```
pip install -r tools/requirements.txt
pytest tools/
```

---

## How it is put together

The app is offline first. All data lives in a local SQLite database on the
phone. The only network calls are the initial card database sync, the optional
re sync from Settings, and downloading a card's artwork the first time it is
shown.

| Layer | Choice |
|---|---|
| Framework | Flutter, Dart 3, null safe |
| Storage | sqflite, raw SQL in hand written DAOs, no ORM |
| State | Riverpod, with code generation |
| Navigation | go_router |
| Models | freezed and json_serializable |
| HTTP | dio |
| Camera and OCR | camera, google_mlkit_text_recognition |
| Image processing | opencv_core |

```
lib/
  core/          theme tokens, router, shared helpers
  data/          database, DAOs, API clients, repositories, CSV import/export
  models/        card, printing, collection entry, enums, settings
  features/      home, scan, collection, add_card, statistics, sync, settings
  shared/        reusable widgets
test/            mirrors lib/
tools/           host side Python tools, not shipped in the app
assets/          card_hashes.json, the bundled artwork index
docs/            design notes and pipeline reviews
```

### The artwork index

`assets/card_hashes.json` is a generated file that ships inside the app. It
holds a 256 bit perceptual hash of every card's artwork, about 14,600 entries.
The app hashes what it sees through the camera and finds the closest entries by
Hamming distance.

The file is committed to the repository, so a normal build does not need to
regenerate it. If the card database gains new cards and you want to rebuild it,
see [tools/README.md](tools/README.md). Rebuilding respects the YGOPRODeck API
policy: images are downloaded once into a local cache, never hotlinked, and
only the derived hashes are shipped.

---

## Troubleshooting

**Errors about missing `.g.dart` or `.freezed.dart` files.** Run step 6 above.

**`flutter doctor` complains about Android licences.** Run
`flutter doctor --android-licenses` and press `y` at every prompt.

**The build fails right after cloning.** Run `flutter clean`, then
`flutter pub get`, then step 6 again.

**The app installs but the card list is empty.** The first launch has to sync
the card database from the internet. Check your connection, then use
Settings, Card database, Re sync.

**Scanning does not recognise anything.** The card has to sit on a surface that
contrasts with it, since the detector finds the card by its edges. Fill the
orange guide box with the card, avoid glare, and hold reasonably still. Turning
on Settings, Scanning, Show diagnostics displays a live readout of what the
camera and matcher are actually seeing.

---

## Credits

Card data and images come from the [YGOPRODeck API](https://ygoprodeck.com/api-guide/).
Yu-Gi-Oh is a trademark of Konami. This project is unofficial and non
commercial.
