# Start 7 Plus

Steventechno's start menu widget (Windows 7 or Windows 9x style), version
3.2.2, from https://github.com/ffseestevanli-oss/Start7Plus-KDE (GPL-2.0+).
DeskDroid ships it as a widget: right-click the panel's Kickoff button, Show
Alternatives, or Add Widgets → Start 7 Plus.

On Linux it lists apps with Python (`contents/code/*.py`) and starts apps,
opens files and runs commands through `sh`. Android has neither, so DeskDroid
changes it here to use Kicker's ProcessRunner when that can do these things
itself (DeskDroid's plasmashell adds them:
`native/plasma/plasmashell/processrunner-deskdroid.cpp`):

- `ui/main.qml`: the app menu (KDE's categories, the same as Kickoff's), file
  search, user name, default browser, power and session buttons, commands.
- `ui/StartMenu.qml`: starting apps and opening files and places.
- `ui/configManage.qml`: app names and icons in its settings.

Everything else is unchanged. With a stock Plasma the widget sees no such
ProcessRunner and works as before, so these changes can go back upstream.
