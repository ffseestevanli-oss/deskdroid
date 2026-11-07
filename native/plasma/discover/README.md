# Discover on the native desktop

KDE's Discover (Plasma 6.4.5), built like Dolphin: a library QtHost starts
(`../apps/as-library.py`, `build_discover` in `../build-deps.sh`), started
from the menu entry "Discover" (`bin/plasma-discover`).

Discover's own Flatpak backend links libflatpak and installs through
Flatpak's system helper over D-Bus with polkit, none of which DeskDroid has.
`DeskDroidBackend/` is the one backend built instead:

- **Catalog:** Flathub's AppStream catalog, which `flatpak update --appstream`
  keeps in the user installation (`files/flatpak/appstream/flathub/<arch>/active`),
  read with AppStreamQt (`../appstream-qt`). Icons come from the catalog's
  cached icons, ratings and reviews from ODRS like on Linux.
- **First start:** adds Flathub (`flatpak remote-add --user --if-not-exists`)
  and fetches the catalog; later starts show the old catalog while a fresh
  one downloads.
- **Install, update, remove:** `flatpak install|update|uninstall --user -y`,
  through DeskDroid's `flatpak` command (`../../flatpak`), with progress read
  from its "Installing 1/3… 45%" lines (`--noninteractive` prints none).
- **Installed apps and updates:** `flatpak list --user --app` and
  `flatpak remote-ls --user --updates --app`.
- **Launch:** `flatpak run <app>`.

Left out for now: store.kde.org add-ons (KNS), the notifier and the updates
page in System Settings, Flatpak permissions and sizes (the catalog has none),
and other remotes than Flathub.

Checked on desktop Linux (2026-11-07): Flathub's x86_64 catalog loads
(3,348 desktop apps, all with a Flatpak bundle), search ranks by name, icons
resolve, and `flatpak install -y` output gives the progress lines parsed here.
