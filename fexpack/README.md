# The FEX add-on APK

`io.deskdroid.fex` carries DeskDroid's FEX-Emu build (`fex/build.sh`) as an
APK, so FEX can travel like any other app (a file share, a chat upload,
F-Droid later) while it has no download host. It has no code and no screen.
When it is installed, and signed with the same key as DeskDroid
(`app/debug.keystore`), the app copies FEX from it instead of downloading
the `fex-latest` release (`X86.kt`). The Steam Installation Assistant shows
whether it is installed (Download from…).

Build it from `fex/build.sh`'s output folder:

    fex/build.sh /tmp/fex-out                  # on arm64 Debian trixie (or CI)
    ./gradlew -p fexpack assembleDebug -PfexDir=/tmp/fex-out [-PdeskdroidBuildNumber=N]

The APK is `fexpack/build/outputs/apk/debug/deskdroid-fex-debug.apk`. With
`-PwithRootfs=true` it also carries the x86 system (`fex/rootfs.sh`'s
`deskdroid-x86-rootfs.*`, about 1.2 GB more), so nothing at all is downloaded.

Only the x86 system then still downloads, from the folder in
`~/.config/deskdroid-fex-url` (the assistant's Download from…) or the
`fex-latest` release. That file takes one folder URL, and/or
`NAME=URL` lines for hosts that give each file its own link (Google Drive,
Discord); `NAME.sha256=` takes the checksum itself as well as a link.
