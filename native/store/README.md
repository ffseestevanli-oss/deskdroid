# DeskDroid app store: apps from other repositories

`apps.json` is the list of apps the store builds from their own git
repositories. Each entry has:

| key | meaning |
|---|---|
| `id` | the app's command and package name (`bin/<id>`, `<id>.zip` in the store) |
| `repo` | the git repository to build from |
| `branch` | the branch to follow; every new commit on it is a new store version |
| `recipe` | `recipes/<recipe>.sh`, how to build it for Android |

How it stays up to date:

- Every APK build (`.github/workflows/android.yml`) runs `build-apps.sh`, which
  builds the newest commit of each listed app into DeskDroid's Qt prefix.
  `native/nativedesk/build.sh` then packages them for the store like Gwenview,
  and the catalog (`index.json`) records the commit each package came from.
  Changing `apps.json` or a recipe on `main` therefore rebuilds the store.
- `.github/workflows/store-watch.yml` checks every few hours whether a listed
  branch has moved past the commit in the published catalog (`store-latest`),
  and if so starts a new build of `main`, which publishes the new version.

## Adding an app

1. Add an entry to `apps.json`.
2. Write `recipes/<recipe>.sh`. It runs with these variables set:
   `STORE_ID`, `STORE_SRC` (the checked-out repository), `STORE_SHA` (its
   commit), `STORE_WORK` (an empty scratch folder), `PREFIX` (DeskDroid's Qt
   prefix for Android), `NDK`, `API` and `QT_HOST_PATH` (desktop Qt, for moc
   and friends). It must install:
   - `$PREFIX/lib/lib<id>.so`, a library with QtHost's entry point
     (`native/plasma/kwin-nativedesk/qthost_entry.cpp`, see
     `native/plasma/apps/as-library.py` for CMake projects with a `main()`);
   - `$PREFIX/share/applications/<id>.desktop` with `Exec=<id>`;
   - its icon under `$PREFIX/share/icons/hicolor/` (a 128x128 PNG becomes the
     store's icon);
   - optionally `$PREFIX/share/metainfo/<id>.metainfo.xml` with a
     `<release version="...">`, the version the store shows.
