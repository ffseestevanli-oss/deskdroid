# Wallpapers

Plasma wallpaper packages that go into the APK as `share/wallpapers/<name>`
(native/nativedesk/build.sh copies every folder here with a metadata.json).

- `DeskDroid`: DeskDroid's own, the default (the Debian trixie desktop's,
  rendered by rootfs/wallpaper/make-wallpaper.py).
- `DDPartyGlass`: DD Party Glass's (the default global theme's), made by theme/dd-party/gen/native.sh.
  The flat DD Party's wallpaper comes with its download in Software.
- DeskDroid's own set, by Steven: `AboveTheWeather`, `Breach`, `Lightfall`,
  `PrismSkyline`, `RelicsAfloat`, `SevenVoices`, `ShardsOfDawn`,
  `VisitorAtDusk`, `WovenSignal`. One image each at its own size (most are
  5040x2160), JPEG quality 88; Plasma crops it to the screen.
- `Next`: Plasma 6's default, from breeze 6.4.5 (CC-BY-SA-4.0).
- `Altai`, `Flow`, `Honeywave`, `Kay`, `MilkyWay`, `Mountain`, `ScarletTree`,
  `Volna`: from plasma-workspace-wallpapers 6.4.5 (see each metadata.json for
  author and license).

Plasma's packages come at 5120x2880 and wider in PNG. Here each has a 3840x2160
JPEG (quality 85) and its phone-sized portrait image, light and dark where the
original has both; ultrawide sizes are left out. The metadata's Id is the
folder's name (Mountain's upstream metadata says "Next").

To add a wallpaper: a folder with a metadata.json (`{"KPlugin": {"Id": ..., "Name": ...}}`)
and contents/images/<width>x<height>.<jpg|png>, Plasma picks the size closest
to the screen.
