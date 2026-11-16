# Inkstone: put it on your iPhone

Inkstone is a free HSK vocabulary app with lock screen, home screen and StandBy widgets. You build it yourself with Xcode on your Mac and install it on your iPhone with your normal Apple ID. No paid developer account is needed.

You need:

- A Mac with Xcode 16 or newer (free in the Mac App Store; it is a large download).
- An iPhone on iOS 17 or newer, and its cable.
- Your Apple ID.

It takes about 15 minutes the first time, most of it waiting for Xcode to download.

## 1. Open the project

1. Install Xcode from the Mac App Store and open it once. If it offers to install the iOS platform, say yes.
2. Unzip `Inkstone.zip` and double-click `Inkstone.xcodeproj`.

## 2. Sign in with your Apple ID

1. In Xcode's menu bar, choose **Xcode → Settings → Accounts**.
2. Click **+**, choose **Apple ID**, and sign in.

## 3. Let Xcode sign the app

1. In the left sidebar, click the blue **Inkstone** project icon at the top.
2. In the middle panel, under **TARGETS**, click **Inkstone**, then the **Signing & Capabilities** tab.
3. Make sure **Automatically manage signing** is ticked, and set **Team** to *your name (Personal Team)*.
4. Click **InkstoneWidget** under TARGETS and set the same **Team** there.

If Xcode shows a red error that the bundle identifier "is not available", open `Config/Signing.xcconfig` in the sidebar, change the last word of `INKSTONE_BUNDLE_PREFIX` (for example to `app.inkstone.yourname2026`), and press **Try Again**.

If the **App Groups** box shows the group in red, click the small refresh button next to it. The app and its widgets share your progress through this group.

## 4. Get your iPhone ready

1. Plug the iPhone into the Mac and tap **Trust** on the phone.
2. On the iPhone, open **Settings → Privacy & Security → Developer Mode**, turn it on and let the phone restart. (The option appears only after the phone has been connected to Xcode.)

## 5. Install

1. At the top of the Xcode window, click the device menu and choose your iPhone.
2. Press the **▶** button (or ⌘R). The first build takes a minute or two.
3. The first time, the iPhone may say "Untrusted Developer". Open **Settings → General → VPN & Device Management**, tap your Apple ID, and tap **Trust**. Then open Inkstone.

## 6. Add the widgets

**Lock screen:** lock the phone, press and hold the lock screen, tap **Customize → Lock Screen**, tap the box under the clock, and choose Inkstone. The wide widget shows the word, pinyin and meaning. Tap the date line above the clock to add the one-line version there too.

**Home screen:** press and hold an empty area, tap **Edit → Add Widget**, and search for Inkstone. The medium and large sizes show an example sentence and have **Next** and **I know it** buttons.

**Choose what it shows:** press and hold a widget, tap **Edit Widget**, and pick the words (smart mix, today's words, words you are learning, your level or saved words), how often it changes, and whether to show pinyin and meaning.

**StandBy:** charge the phone on its side; the small widget works there too.

## Good to know

- **The 7-day limit.** With a free Apple ID, apps you build yourself stop opening after 7 days. Plug the phone in and press ▶ again; your progress is kept. A paid Apple Developer account ($99 a year) makes it last a year.
- **A nicer voice.** Pronunciation uses the Chinese voice built into iOS. For a more natural one, download an enhanced voice in **Settings → Accessibility → Spoken Content → Voices → Chinese**.
- **Your data stays on the phone.** No account, no tracking. Use **Progress → Settings → Export progress** to keep a backup.

## What is in the folder

| Folder | Contents |
| --- | --- |
| `App` | The app: screens, study session, dictionary, stroke data |
| `Widget` | The lock screen, home screen and StandBy widgets |
| `Shared` | Code and data used by both: spaced repetition (FSRS), progress, theme, font |
| `Tests` | Unit tests (⌘U in Xcode) |
| `Config` | Signing settings, Info.plist files and entitlements |

Data sources and licences are listed in `CREDITS.md`.
