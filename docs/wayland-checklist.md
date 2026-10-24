# Plasma Wayland session: device test checklist

Step A of the Wayland plan (plan.md, section 6): Plasma's Wayland session
running nested inside Termux:X11, offered as an experimental option next to the
X11 session. Untested on a device so far.

## How it works

Settings → Desktop session → Wayland (experimental) sets `DESKDROID_SESSION=wayland`.
`deskdroid-session` then runs `startplasma-wayland` instead of `startplasma-x11`.
Plasma's `plasma_session` starts `kwin_wayland_wrapper --xwayland`, which runs
`kwin_wayland` from `PATH`; the session puts `/usr/local/lib/deskdroid/wayland`
first, where `kwin_wayland` links to `deskdroid-kwin-wayland`. That adds KWin's
X11 backend options (`--x11-display`, `--width`/`--height` from the X screen,
`--scale` from the desktop scale) and runs the real `/usr/bin/kwin_wayland`.

KWin opens one window covering Termux:X11's screen and draws the whole Wayland
desktop into it. There's no render node under proot, so KWin uses QPainter
(`KWIN_COMPOSE=Q`) and hands frames to the X server through MIT-SHM and Present,
which Termux:X11 builds in. Apps use Mesa's llvmpipe; the Graphics setting is
ignored and the Venus server isn't started. X11 apps run on Xwayland (`:1`).

Images built before this change don't have `kwin-wayland`, `xwayland` or
`qt6-wayland`; the session logs `... missing (reinstall the system for Wayland)`
and starts X11. Ultra-lite (MATE) is X11 only.

## Known limits

- Rotating the phone or plugging in a monitor changes the X screen; no window
  manager runs there, so `deskdroid-kwin-wayland` checks the screen size every
  second and resizes KWin's window with `xdotool`, and KWin resizes its output.
  The log shows `deskdroid-kwin-wayland: screen W H, sized KWin's window ...`
  at start and on each change. Images without `xdotool` keep the old size.
- Software rendering only, plus one extra copy per frame into the X server.
- Plasma's lock screen at start isn't used (startplasma-wayland passes `--no-lockscreen`).

## Checklist

1. Install an image built after this change (Settings → Reinstall the system).
2. Settings → Desktop session → Wayland (experimental), then start the desktop.
3. Share log. Expect `deskdroid-session: wayland session, GPU mode llvmpipe`.
   `Present X11 extension is unavailable` or `SHM ... not shared pixmaps` from
   KWin means the X server lacks what KWin's X11 backend needs.
4. Desktop fills the screen with the panel at the bottom, at the chosen scale.
5. Touchpad and direct touch both move the pointer and click; keyboard types in Konsole.
6. Konsole: `echo $XDG_SESSION_TYPE $WAYLAND_DISPLAY $DISPLAY` prints
   `wayland wayland-0 :1` (or similar).
7. An X11 app (`xmessage hi`, Floorp on Full) opens through Xwayland.
8. Switch back to Plasma X11: the next start is the X11 desktop with its usual scale.
9. Rotate the phone with auto-rotate on: the desktop resizes to the new
   orientation within a second, panel and wallpaper included.

## Results so far

- 2026-10-23: works with llvmpipe and Venus. Rotation didn't resize the
  desktop; fixed by following RandR screen changes.
- 2026-10-24: still no resize with that fix on the phone (RandR events or the
  window lookup didn't work there). Replaced with polling the screen size,
  which logs each resize.
- 2026-10-24: the log from the polling image had no `deskdroid-kwin-wayland`
  lines at all, so either the watcher never found KWin's window (it stayed
  silent then) or the script didn't run. It now logs `starting KWin` when it
  runs, finds the window by any large top-level window as a last resort, and
  lists the X windows if it finds none within 15 s.
