**First alpha of DeskDroid's native desktop.** KDE Plasma running as Android code: no proot, no Linux system to download, drawn with your phone's own GPU. This is a debug test build (build 200 of the native desktop work), so expect bugs.

**Install:** download `deskdroid-0.1.0-alpha-build-200.apk` below on an arm64 phone with Android 10 or newer. It installs over earlier DeskDroid builds. Then tap **Start desktop**.

### What's in it
- KWin and plasmashell with a panel, the Kickoff menu and a Folder View desktop showing your phone's Desktop folder and wallpaper
- Dolphin, KWrite and Gwenview, in Breeze Dark with Breeze Dark icons
- Panel editing (edit mode, panel settings, widget explorer)
- Rotation that follows the phone, and a scale that's automatic by default and changes instantly
- Touchpad or direct touch, keyboard and mouse; the phone's keyboard pops up for text fields
- Back opens DeskDroid's side menu; End Session uses KDE's logout screen
- Launcher mode: make DeskDroid your home app, with your Android apps in Kickoff's Android Apps folder and Restart or Power Off opening Android's power menu
- Open files in Android apps from Dolphin and the desktop (Open With)
- The previous Debian (proot) desktop is still there under Settings → Legacy

### Known limits
- Alpha and debug-signed; mainly tested on a Pixel 10 Pro. Other phones and GPUs may not start the desktop.
- No app store yet: it arrives in the next alpha. Apps are only the built-in ones above.
- No web browser on the native desktop yet (Floorp is on the way). Use an Android browser from Android Apps, or the legacy Debian desktop.
- No Steam or x86 apps on the native desktop yet (FEX-Emu is on the roadmap); they still run on the legacy desktop.
- No screen lock in Plasma, and many Plasma widgets and System Settings pages aren't built yet.
- One screen at a time; full external monitor support is still to come.
- Restart or Power Off asks you to turn on "DeskDroid power menu" in Accessibility settings the first time.

If something breaks, a log from DeskDroid's menu helps a lot.
