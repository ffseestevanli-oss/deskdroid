"""DD Party icon theme: chamfered folders, files and app tiles in the party look.
Covers places, common file types, devices and the core KDE apps; everything else
is inherited from Breeze Dark."""
import os, sys, base64, shutil
from palette import *

# Glyphs on a 24-unit grid, drawn with strokes (fill noted where used).
G = {
    "home": '<path d="M4 11 L12 4 L20 11 V20 H4 Z M10 20 V14 H14 V20"/>',
    "desktop": '<path d="M3 4 H21 V16 H3 Z M9 20 H15 M12 16 V20"/>',
    "documents": '<path d="M6 3 H14 L18 7 V21 H6 Z M9 11 H15 M9 15 H15"/>',
    "download": '<path d="M12 4 V15 M7 10 L12 15 L17 10 M5 20 H19"/>',
    "music": '<path d="M9 18 V6 L19 4 V16"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="16.5" cy="16" r="2.5"/>',
    "pictures": '<path d="M3 5 H21 V19 H3 Z M3 16 L9 10 L14 15 L17 12 L21 16"/><circle cx="16" cy="9" r="1.6"/>',
    "videos": '<path d="M3 5 H21 V19 H3 Z"/><path d="M10 9 L15 12 L10 15 Z" class="f"/>',
    "templates": '<path d="M4 4 H20 V20 H4 Z M4 10 H20 M10 10 V20"/>',
    "globe": '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12 H20.5 M12 3.5 C8 7 8 17 12 20.5 M12 3.5 C16 7 16 17 12 20.5"/>',
    "games": '<path d="M6 9 H18 C20 9 21 11 21 13 L20 17 C19.5 19 17.5 19 16.5 17.5 L15 16 H9 L7.5 17.5 C6.5 19 4.5 19 4 17 L3 13 C3 11 4 9 6 9 Z M8 11.5 V14.5 M6.5 13 H9.5"/><circle cx="15.5" cy="12" r=".9" class="f"/><circle cx="17.5" cy="14" r=".9" class="f"/>',
    "code": '<path d="M8 8 L4 12 L8 16 M16 8 L20 12 L16 16 M14 6 L10 18"/>',
    "cloud": '<path d="M7 18 H17 A4 4 0 0 0 17 10 A6 6 0 0 0 6 11 A3.5 3.5 0 0 0 7 18 Z"/>',
    "trash": '<path d="M5 7 H19 M9 7 V4 H15 V7 M7 7 L8 20 H16 L17 7 M10.5 10.5 V16.5 M13.5 10.5 V16.5"/>',
    "star": '<path d="M12 3.5 L14.6 9 L20.5 9.6 L16 13.6 L17.3 19.5 L12 16.5 L6.7 19.5 L8 13.6 L3.5 9.6 L9.4 9 Z"/>',
    "lock": '<path d="M6 11 H18 V20 H6 Z M8.5 11 V8 A3.5 3.5 0 0 1 15.5 8 V11"/>',
    "text": '<path d="M5 6 H19 M5 10 H19 M5 14 H16 M5 18 H12"/>',
    "archive": '<path d="M4 8 H20 V20 H4 Z M4 8 L6 4 H18 L20 8 M10 12 H14"/>',
    "gear": '<circle cx="12" cy="12" r="3"/><path d="M12 3 V5.5 M12 18.5 V21 M3 12 H5.5 M18.5 12 H21 M5.6 5.6 L7.4 7.4 M16.6 16.6 L18.4 18.4 M5.6 18.4 L7.4 16.6 M16.6 7.4 L18.4 5.6"/><circle cx="12" cy="12" r="6.5"/>',
    "terminal": '<path d="M5 8 L9 12 L5 16 M11 17 H19"/>',
    "calc": '<path d="M6 3 H18 V21 H6 Z M8.5 5.5 H15.5 V9 H8.5 Z"/><circle cx="9" cy="12.5" r=".9" class="f"/><circle cx="12" cy="12.5" r=".9" class="f"/><circle cx="15" cy="12.5" r=".9" class="f"/><circle cx="9" cy="15.5" r=".9" class="f"/><circle cx="12" cy="15.5" r=".9" class="f"/><circle cx="15" cy="15.5" r=".9" class="f"/><circle cx="9" cy="18.5" r=".9" class="f"/><circle cx="12" cy="18.5" r=".9" class="f"/><circle cx="15" cy="18.5" r=".9" class="f"/>',
    "bag": '<path d="M5 8 H19 L18 21 H6 Z M9 8 V6 A3 3 0 0 1 15 6 V8"/>',
    "pen": '<path d="M4 20 L5 15 L16 4 L20 8 L9 19 Z M14 6 L18 10"/>',
    "camera": '<path d="M4 8 H8 L10 5 H14 L16 8 H20 V19 H4 Z"/><circle cx="12" cy="13" r="3.5"/>',
    "chart": '<path d="M4 20 H20 M7 17 V12 M11 17 V7 M15 17 V10 M19 17 V5"/>',
    "info": '<circle cx="12" cy="12" r="8.5"/><path d="M12 11 V17"/><circle cx="12" cy="7.8" r="1.1" class="f"/>',
    "help": '<circle cx="12" cy="12" r="8.5"/><path d="M9.5 9.5 C9.5 6.5 14.5 6.5 14.5 9.5 C14.5 11.5 12 11.5 12 14"/><circle cx="12" cy="17" r="1.1" class="f"/>',
    "box": '<path d="M4 8 L12 4 L20 8 V16 L12 20 L4 16 Z M4 8 L12 12 L20 8 M12 12 V20"/>',
    "disc": '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="2.5"/>',
    "font": '<path d="M6 20 L12 4 L18 20 M8.5 14 H15.5"/>',
    "play": '<path d="M8 5 L19 12 L8 19 Z"/>',
    "sheet": '<path d="M4 4 H20 V20 H4 Z M4 10 H20 M4 15 H20 M10 4 V20"/>',
    "slides": '<path d="M4 4 H20 V15 H4 Z M12 15 V20 M8 20 H16 M8 12 V10 M12 12 V7 M16 12 V9"/>',
    "bolt": '<path d="M13 3 L5 14 H11 L10 21 L19 10 H13 Z"/>',
    "window": '<path d="M3 5 H21 V19 H3 Z M3 9 H21"/><circle cx="6" cy="7" r=".8" class="f"/><circle cx="8.5" cy="7" r=".8" class="f"/>',
    "braces": '<path d="M9 4 C6 4 7 9 5 12 C7 15 6 20 9 20 M15 4 C18 4 17 9 19 12 C17 15 18 20 15 20"/>',
    "markdown": '<path d="M3 7 H21 V17 H3 Z M6 14 V10 L8.5 12.5 L11 10 V14 M16 10 V14 M14 12 L16 14 L18 12"/>',
    "unknown": '<path d="M9.5 9 C9.5 6 14.5 6 14.5 9 C14.5 11.5 12 11.5 12 14.5"/><circle cx="12" cy="18" r="1.1" class="f"/>',
    "phone": '<path d="M7 2.5 H17 V21.5 H7 Z M11 18.5 H13"/>',
    "harddisk": '<path d="M3 7 H21 V17 H3 Z M6 12 H12"/><circle cx="17" cy="12" r="1.2" class="f"/>',
    "usb": '<path d="M12 3 V16 M9 6 L12 3 L15 6 M12 12 L8 9.5 V8 M12 10 L16 7.5 V6.5"/><circle cx="12" cy="18.5" r="2.2"/>',
    "sdcard": '<path d="M7 3 H15 L18 6 V21 H7 Z M10 3 V7 M13 3 V7"/>',
    "keyboard": '<path d="M3 6 H21 V18 H3 Z M7 15 H17 M6 9 H7 M9 9 H10 M12 9 H13 M15 9 H16 M18 9 H18.5 M6 12 H7 M9 12 H10 M12 12 H13 M15 12 H16"/>',
    "mouse": '<path d="M7 8 L10 3 H14 L17 8 V17 L14 21 H10 L7 17 Z M12 3 V9"/>',
    "headphones": '<path d="M4 16 V12 A8 8 0 0 1 20 12 V16"/><path d="M4 14 H7 V20 H4 Z M17 14 H20 V20 H17 Z"/>',
    "printer": '<path d="M6 9 V4 H18 V9 M4 9 H20 V17 H4 Z M7 14 H17 V20 H7 Z"/>',
    "computer": '<path d="M3 4 H21 V16 H3 Z M9 20 H15 M12 16 V20 M3 13 H21"/>',
    "search": '<circle cx="10.5" cy="10.5" r="6"/><path d="M15 15 L20 20"/>',
    "mail": '<path d="M3 6 H21 V18 H3 Z M3 6 L12 13 L21 6"/>',
    "folder": '<path d="M3 7 L6 4 H10 L12 6 H21 V19 H3 Z M3 9 H21"/>',
    "image": '<path d="M3 5 H21 V19 H3 Z M3 16 L9 10 L14 15 L17 12 L21 16"/><circle cx="16" cy="9" r="1.6"/>',
    "pdf": '<path d="M5 6 H19 M5 10 H19 M5 14 H14"/><path d="M14 15 H20 V20 H14 Z" class="f"/>',
    "debian": '<path d="M4 8 L12 4 L20 8 V16 L12 20 L4 16 Z M4 8 L12 12 L20 8 M12 12 V20 M8 6 L16 10"/>',
    "palette": '<path d="M12 3.5 A8.5 8.5 0 1 0 12 20.5 C14 20.5 13.5 18 15 17 C16.5 16 20.5 17.5 20.5 12 A8.5 8.5 0 0 0 12 3.5 Z"/><circle cx="8" cy="11" r="1.2" class="f"/><circle cx="11" cy="7.5" r="1.2" class="f"/><circle cx="15.5" cy="8.5" r="1.2" class="f"/>',
    "wine": '<path d="M8 3 H16 L15.5 9 A3.5 3.5 0 0 1 8.5 9 Z M12 12.5 V19 M8.5 20 H15.5"/>',
    "cap": '<path d="M2.5 9.5 L12 5 L21.5 9.5 L12 14 Z M6.5 11.5 V16 C9 18.5 15 18.5 17.5 16 V11.5 M21.5 9.5 V15"/>',
    "flask": '<path d="M9.5 3.5 H14.5 M10.5 3.5 V9.5 L5 19 C4.5 20 5 20.5 6 20.5 H18 C19 20.5 19.5 20 19 19 L13.5 9.5 V3.5 M7.5 15 H16.5"/>',
    "toolbox": '<path d="M3.5 9 H20.5 V19 H3.5 Z M9 9 V6 H15 V9 M3.5 13.5 H20.5 M10.5 12 V15 M13.5 12 V15"/>',
    "power": '<path d="M12 3.5 V11.5 M7.2 6.5 A7.5 7.5 0 1 0 16.8 6.5"/>',
    "reboot": '<path d="M19.5 12 A7.5 7.5 0 1 1 16.8 6.2 M17.5 2.8 V6.8 H13.5"/>',
    "moon": '<path d="M15.5 3.8 A8.5 8.5 0 1 0 20.2 15.5 A7 7 0 0 1 15.5 3.8 Z"/>',
    "logout": '<path d="M14 4 H20 V20 H14 M4 12 H14 M8 8 L4 12 L8 16"/>',
    "clock": '<circle cx="12" cy="12" r="8.5"/><path d="M12 7 V12 L15.5 14"/>',
    "grid": '<path d="M4 4 H10 V10 H4 Z M14 4 H20 V10 H14 Z M4 14 H10 V20 H4 Z M14 14 H20 V20 H14 Z"/>',
    "compass": '<circle cx="12" cy="12" r="8.5"/><path d="M15.5 8.5 L13.2 13.2 L8.5 15.5 L10.8 10.8 Z"/>',
}


def glyph(name, cx, cy, scale, color, sw=2.0):
    body = G[name].replace('class="f"', f'fill="{color}" stroke="none"')
    return (f'<g transform="translate({cx - 12 * scale:.2f},{cy - 12 * scale:.2f}) scale({scale})" fill="none" '
            f'stroke="{color}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round">{body}</g>')


def doc(svgbody):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">{svgbody}</svg>\n'


def folder(color, g=None, open_=False):
    s = (f'<path d="M4 13 L11 6 H26 L31 11 H60 V51 L53 58 H4 Z" fill="#14141F" stroke="{color}" stroke-width="2.5" stroke-linejoin="round"/>'
         f'<path d="M5 20 H59 V50.5 L52.5 57 H5 Z" fill="{color}" fill-opacity="{0.30 if open_ else 0.18}"/>'
         f'<path d="M4 20 H60" stroke="{color}" stroke-width="2"/>'
         f'<rect x="5.2" y="53" width="24" height="3.6" fill="{color}"/>')
    if g:
        s += glyph(g, 32, 37, 0.85, color, 2.2)
    return doc(s)


def filetype(color, g):
    s = (f'<path d="M11 4 H40 L53 17 V52 L46 59 H11 Z" fill="#14141F" stroke="#3A3A52" stroke-width="2.2" stroke-linejoin="round"/>'
         f'<path d="M40 4 V17 H53" fill="none" stroke="#3A3A52" stroke-width="2.2" stroke-linejoin="round"/>'
         f'<rect x="12.2" y="53.5" width="22" height="4.4" fill="{color}"/>'
         + glyph(g, 32, 32, 1.1, color, 2.1))
    return doc(s)


def tile(color, g, bar=None):
    bar = bar or color
    fill_bar = "url(#rb)" if bar == "rainbow" else bar
    s = (f'<defs><linearGradient id="rb" x1="0" x2="1">{rainbow_stops()}</linearGradient></defs>'
         f'<path d="M4 14 L14 4 H60 V50 L50 60 H4 Z" fill="{CARD}" stroke="{BORDER}" stroke-width="2" stroke-linejoin="round"/>'
         f'<path d="M5 52 H58 L54 56 V56 L52 58 H5 Z" fill="{fill_bar}"/>'
         + glyph(g, 32, 29.5, 1.35, color, 2.0))
    return doc(s)


def start_icon():
    """The application menu button: the tile shape in #990045 with a menu key's three lines."""
    s = (f'<defs><linearGradient id="rb" x1="0" x2="1">{rainbow_stops()}</linearGradient></defs>'
         f'<path d="M4 14 L14 4 H60 V50 L50 60 H4 Z" fill="{MAGENTA}" stroke="{MAGENTA_HI}" stroke-width="2" stroke-linejoin="round"/>'
         f'<path d="M5 52 H58 L54 56 V56 L52 58 H5 Z" fill="url(#rb)"/>'
         f'<g stroke="{TEXT}" stroke-width="5" stroke-linecap="round">'
         '<path d="M17 18 H47"/><path d="M17 29 H47"/><path d="M17 40 H47"/></g>')
    return doc(s)


def logo(png_path):
    b64 = base64.b64encode(open(png_path, "rb").read()).decode()
    return ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="64" height="64" viewBox="0 0 64 64">'
            f'<image width="64" height="64" xlink:href="data:image/png;base64,{b64}"/></svg>\n')


FOLDER_PINK = MAGENTA_TEXT

PLACES = {
    "folder": (FOLDER_PINK, None), "inode-directory": (FOLDER_PINK, None),
    "folder-open": (FOLDER_PINK, None, True), "folder-drag-accept": (FOLDER_PINK, None, True),
    "user-home": (CYAN, "home"), "folder-home": (CYAN, "home"),
    "user-desktop": (PURPLE, "desktop"), "folder-desktop": (PURPLE, "desktop"),
    "folder-documents": (YELLOW, "documents"), "folder-text": (YELLOW, "text"),
    "folder-download": (GREEN, "download"), "folder-downloads": (GREEN, "download"),
    "folder-music": (ORANGE, "music"), "folder-sound": (ORANGE, "music"),
    "folder-pictures": (PINK, "pictures"), "folder-images": (PINK, "pictures"), "folder-image": (PINK, "pictures"),
    "folder-videos": (RED, "videos"), "folder-video": (RED, "videos"), "folder-movies": (RED, "videos"),
    "folder-templates": (SOFT, "templates"), "folder-publicshare": (CYAN, "globe"),
    "folder-network": (CYAN, "globe"), "folder-remote": (CYAN, "globe"), "network-workgroup": (CYAN, "globe"),
    "folder-cloud": (CYAN, "cloud"), "folder-games": (GREEN, "games"),
    "folder-development": (PURPLE, "code"), "folder-script": (PURPLE, "code"), "folder-git": (ORANGE, "code"),
    "folder-favorites": (YELLOW, "star"), "folder-bookmark": (YELLOW, "star"), "bookmarks": (YELLOW, "star"),
    "folder-locked": (RED, "lock"), "folder-root": (RED, "lock"), "folder-recent": (CYAN, "search"),
    "folder-windows": (ORANGE, "wine"),
}

MIMES = {
    "text-plain": (SOFT, "text"), "text-x-generic": (SOFT, "text"), "application-x-zerosize": (SOFT, "text"),
    "text-x-log": (DIM, "text"),
    "text-markdown": (CYAN, "markdown"), "text-x-markdown": (CYAN, "markdown"),
    "text-html": (ORANGE, "globe"), "application-xhtml+xml": (ORANGE, "globe"),
    "application-json": (YELLOW, "braces"), "text-x-csrc": (PURPLE, "code"), "text-x-c++src": (PURPLE, "code"),
    "text-x-python": (GREEN, "code"), "text-x-python3": (GREEN, "code"), "application-javascript": (YELLOW, "code"),
    "text-javascript": (YELLOW, "code"), "text-x-script": (GREEN, "terminal"), "application-x-shellscript": (GREEN, "terminal"),
    "text-x-kotlin": (PURPLE, "code"), "text-x-qml": (CYAN, "code"), "text-xml": (ORANGE, "code"), "application-xml": (ORANGE, "code"),
    "image-x-generic": (PINK, "image"), "image-png": (PINK, "image"), "image-jpeg": (PINK, "image"), "image-gif": (PINK, "image"),
    "image-webp": (PINK, "image"), "image-svg+xml": (GREEN, "pen"), "image-x-xcf": (ORANGE, "palette"), "application-x-krita": (PURPLE, "palette"),
    "audio-x-generic": (ORANGE, "music"), "audio-mpeg": (ORANGE, "music"), "audio-flac": (ORANGE, "music"),
    "audio-x-wav": (ORANGE, "music"), "audio-ogg": (ORANGE, "music"), "audio-x-vorbis+ogg": (ORANGE, "music"),
    "video-x-generic": (RED, "play"), "video-mp4": (RED, "play"), "video-webm": (RED, "play"), "video-x-matroska": (RED, "play"),
    "application-pdf": (RED, "pdf"),
    "application-zip": (ORANGE, "archive"), "application-x-tar": (ORANGE, "archive"), "application-x-compressed-tar": (ORANGE, "archive"),
    "application-x-7z-compressed": (ORANGE, "archive"), "application-x-rar": (ORANGE, "archive"), "application-x-xz-compressed-tar": (ORANGE, "archive"),
    "application-x-bzip-compressed-tar": (ORANGE, "archive"), "application-gzip": (ORANGE, "archive"), "application-x-archive": (ORANGE, "archive"),
    "application-x-zstd-compressed-tar": (ORANGE, "archive"),
    "application-x-executable": (GREEN, "bolt"), "application-x-sharedlib": (DIM, "gear"), "application-x-object": (DIM, "gear"),
    "application-x-ms-dos-executable": (CYAN, "window"), "application-x-msdownload": (CYAN, "window"), "application-x-msi": (CYAN, "box"),
    "application-x-ms-shortcut": (CYAN, "window"),
    "application-vnd.debian.binary-package": (RED, "debian"), "application-x-deb": (RED, "debian"),
    "application-vnd.flatpak.ref": (CYAN, "box"), "application-vnd.flatpak": (CYAN, "box"), "application-x-appimage": (GREEN, "box"),
    "application-vnd.android.package-archive": (GREEN, "phone"),
    "application-x-iso9660-image": (SOFT, "disc"), "application-x-cd-image": (SOFT, "disc"),
    "font-x-generic": (SOFT, "font"), "font-ttf": (SOFT, "font"), "application-x-font-ttf": (SOFT, "font"), "font-otf": (SOFT, "font"),
    "application-vnd.oasis.opendocument.text": (CYAN, "documents"), "x-office-document": (CYAN, "documents"),
    "application-vnd.openxmlformats-officedocument.wordprocessingml.document": (CYAN, "documents"),
    "application-vnd.oasis.opendocument.spreadsheet": (GREEN, "sheet"), "x-office-spreadsheet": (GREEN, "sheet"),
    "application-vnd.openxmlformats-officedocument.spreadsheetml.sheet": (GREEN, "sheet"), "text-csv": (GREEN, "sheet"),
    "application-vnd.oasis.opendocument.presentation": (ORANGE, "slides"), "x-office-presentation": (ORANGE, "slides"),
    "application-vnd.openxmlformats-officedocument.presentationml.presentation": (ORANGE, "slides"),
    "application-x-desktop": (PURPLE, "bolt"), "text-x-patch": (PURPLE, "code"), "application-x-bittorrent": (GREEN, "download"),
    "unknown": (DIM, "unknown"), "application-octet-stream": (DIM, "unknown"), "application-x-generic": (DIM, "unknown"),
}

DEVICES = {
    "drive-harddisk": (CYAN, "harddisk"), "drive-harddisk-solidstate": (CYAN, "harddisk"), "drive-harddisk-root": (RED, "harddisk"),
    "drive-removable-media": (ORANGE, "usb"), "drive-removable-media-usb": (ORANGE, "usb"), "drive-removable-media-usb-pendrive": (ORANGE, "usb"),
    "media-flash": (YELLOW, "sdcard"), "media-flash-sd-mmc": (YELLOW, "sdcard"), "media-flash-memory-stick": (YELLOW, "sdcard"),
    "drive-optical": (SOFT, "disc"), "media-optical": (SOFT, "disc"),
    "phone": (GREEN, "phone"), "smartphone": (GREEN, "phone"), "multimedia-player": (GREEN, "phone"),
    "computer": (PURPLE, "computer"), "computer-laptop": (PURPLE, "computer"), "video-display": (PURPLE, "desktop"), "monitor": (PURPLE, "desktop"),
    "input-keyboard": (SOFT, "keyboard"), "input-mouse": (SOFT, "mouse"), "input-gaming": (GREEN, "games"), "input-touchpad": (SOFT, "templates"),
    "audio-headphones": (ORANGE, "headphones"), "audio-headset": (ORANGE, "headphones"), "printer": (SOFT, "printer"),
    "network-server": (CYAN, "harddisk"),
}

APPS = {
    "system-file-manager": (CYAN, "folder"), "org.kde.dolphin": (CYAN, "folder"),
    "utilities-terminal": (GREEN, "terminal"), "org.kde.konsole": (GREEN, "terminal"), "konsole": (GREEN, "terminal"), "org.kde.yakuake": (GREEN, "terminal"),
    "systemsettings": (PURPLE, "gear"), "org.kde.systemsettings": (PURPLE, "gear"),
    "plasmadiscover": (PINK, "bag"), "org.kde.discover": (PINK, "bag"), "system-software-install": (PINK, "bag"),
    "org.kde.kate": (YELLOW, "pen"), "kate": (YELLOW, "pen"), "org.kde.kwrite": (YELLOW, "pen"), "accessories-text-editor": (YELLOW, "pen"),
    "org.kde.kcalc": (ORANGE, "calc"), "accessories-calculator": (ORANGE, "calc"),
    "org.kde.ark": (ORANGE, "box"), "ark": (ORANGE, "box"), "utilities-file-archiver": (ORANGE, "box"),
    "org.kde.spectacle": (RED, "camera"), "spectacle": (RED, "camera"), "applets-screenshooter": (RED, "camera"),
    "org.kde.plasma-systemmonitor": (GREEN, "chart"), "utilities-system-monitor": (GREEN, "chart"), "ksysguard": (GREEN, "chart"),
    "org.kde.kinfocenter": (CYAN, "info"), "hwinfo": (CYAN, "info"), 
    "help-browser": (YELLOW, "help"), "org.kde.khelpcenter": (YELLOW, "help"),
    "internet-web-browser": (CYAN, "globe"), "web-browser": (CYAN, "globe"),
    "internet-mail": (RED, "mail"), "mail-client": (RED, "mail"),
    "org.kde.gwenview": (PINK, "image"), "multimedia-photo-viewer": (PINK, "image"),
    "org.kde.okular": (RED, "pdf"), "okular": (RED, "pdf"),
    "multimedia-audio-player": (ORANGE, "music"), "org.kde.elisa": (ORANGE, "music"),
    "multimedia-video-player": (RED, "play"), "org.kde.haruna": (RED, "play"), "org.kde.dragonplayer": (RED, "play"),
    "applications-games": (GREEN, "games"), "applications-development": (PURPLE, "code"),
    "preferences-desktop-theme-global": (PINK, "palette"), "preferences-desktop-color": (PINK, "palette"),
    "preferences-desktop-icons": (YELLOW, "star"), "preferences-desktop-wallpaper": (PINK, "image"),
    "org.kde.plasma.search": (CYAN, "search"), "system-search": (CYAN, "search"),
    "wine": (ORANGE, "wine"),
    # Application menu categories (Kickoff asks for their -symbolic names,
    # which fall back to these within DD-Party)
    "applications-education": (YELLOW, "cap"), "applications-graphics": (PINK, "palette"),
    "applications-internet": (CYAN, "globe"), "applications-network": (CYAN, "globe"),
    "applications-multimedia": (RED, "play"), "applications-office": (CYAN, "documents"),
    "applications-science": (GREEN, "flask"), "applications-system": (PURPLE, "computer"),
    "applications-utilities": (ORANGE, "toolbox"), "applications-toys": (YELLOW, "star"),
    "help-about": (CYAN, "info"), "applications-all": (PINK, "grid"), "compass": (CYAN, "compass"),
    # Recent files and places (Dolphin, Kickoff)
    "document-open-recent": (PURPLE, "clock"), "folder-open-recent": (PURPLE, "clock"), "view-history": (PURPLE, "clock"),
    # Session (Kickoff's footer, the logout screen)
    "system-shutdown": (RED, "power"), "system-reboot": (ORANGE, "reboot"), "system-suspend": (PURPLE, "moon"),
    "system-log-out": (CYAN, "logout"), "system-lock-screen": (YELLOW, "lock"),
}

START_NAMES = ["start-here", "start-here-kde", "start-here-kde-plasma", "start-here-kde-symbolic", "start-here-symbolic",
               "distributor-logo"]
LOGO_NAMES = ["org.deskdroid.app", "deskdroid"]


def write_set(base, d, fn):
    os.makedirs(base, exist_ok=True)
    seen = {}
    for name, spec in d.items():
        key = spec
        if key in seen:
            os.symlink(seen[key] + ".svg", f"{base}/{name}.svg")
            continue
        open(f"{base}/{name}.svg", "w").write(fn(*spec))
        seen[key] = name


# ---- System Settings' pages and other settings icons ----------------------
# Breeze's own artwork for each page (the sidebar needs its details: a mouse,
# a keyboard, a bell...), redrawn in one DD Party colour (duotone: the
# picture's light and shade in that colour) on DD Party's chamfered tile.
# Needs Breeze's icons (DDP_BREEZE, default /usr/share/icons/breeze) and the
# cairosvg module; without them these are left to Breeze Dark.
SETTINGS_EXTRA = ["battery", "krunner", "ktip", "xorg", "system-run", "preferences-system", "kwalletmanager", "krdc",
                  "preferences-desktop", "preferences-system-network", "system-users", "system-lock-screen"]
SETTINGS_SKIP = ("yast-", "amarok", "podcast", "financial-schedule", "face-smile", "window-duplicate", "preferences-git",
                 "preferences-releasenotes", "preferences-virtualization", "plasmagik")
SETTINGS_COLORS = [
    (("network", "web-browser", "bluetooth", "kdeconnect", "kde-connect", "online-accounts", "krdc", "remote"), CYAN),
    (("security", "firewall", "apparmor", "kerberos", "password", "lock", "cryptography", "sudo", "kwallet"), RED),
    (("sound", "multimedia", "mediacontrol", "notification", "speech", "ktip"), ORANGE),
    (("theme", "font", "cursor", "color", "emoticons", "splash", "icons", "wallpaper", "gtk", "plasma"), PINK),
    (("mouse", "keyboard", "touchpad", "tablet", "touchscreen", "gestures", "peripherals", "devices", "printer",
      "scanner", "thunderbolt", "drive", "disk", "removable", "device", "gaming", "battery", "accessibility", "kaccess"), YELLOW),
    (("system", "power", "startup", "services", "session", "performance", "backup", "time", "locale", "user",
      "login", "language", "smart", "log", "kded", "ksmserver", "xorg", "run"), GREEN),
]


def settings_color(name):
    for keys, c in SETTINGS_COLORS:
        if any(k in name for k in keys):
            return c
    return PURPLE


def breeze_icon(base, name):
    for sub in ("preferences/32", "apps/48", "categories/32", "devices/64", "status/64", "actions/32"):
        f = f"{base}/{sub}/{name}.svg"
        if os.path.exists(f):
            return os.path.realpath(f)
    return None


def duotone_tile(color, src, px=72):
    import io
    import numpy as np
    import cairosvg
    from PIL import Image
    png = cairosvg.svg2png(url=src, output_width=px, output_height=px)
    im = np.asarray(Image.open(io.BytesIO(png)).convert("RGBA")).astype(float) / 255
    a = im[..., 3]
    lum = 0.2126 * im[..., 0] + 0.7152 * im[..., 1] + 0.0722 * im[..., 2]
    m = a > 0.05
    lo, hi = (np.percentile(lum[m], 2), np.percentile(lum[m], 98)) if m.any() else (0.0, 1.0)
    t = np.clip((lum - lo) / max(hi - lo, 1e-3), 0, 1)[..., None]
    c = np.array([int(color[i:i + 2], 16) for i in (1, 3, 5)]) / 255
    rgb = (0.25 + 0.75 * t) * c + (t ** 3) * 0.35 * (1 - c)
    out = Image.fromarray((np.dstack([np.clip(rgb, 0, 1), a]) * 255).astype(np.uint8))
    b = io.BytesIO()
    out.quantize(colors=96, method=Image.Quantize.FASTOCTREE).save(b, "PNG", optimize=True)
    b64 = base64.b64encode(b.getvalue()).decode()
    return ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="64" height="64" viewBox="0 0 64 64">'
            f'<path d="M4 14 L14 4 H60 V50 L50 60 H4 Z" fill="{CARD}" stroke="{BORDER}" stroke-width="2" stroke-linejoin="round"/>'
            f'<path d="M5 52 H58 L54 56 V56 L52 58 H5 Z" fill="{color}"/>'
            f'<image x="14" y="10" width="36" height="36" xlink:href="data:image/png;base64,{b64}"/></svg>\n')


def write_settings(out):
    base = os.environ.get("DDP_BREEZE", "/usr/share/icons/breeze")
    try:
        import cairosvg  # noqa: F401
    except ImportError:
        print("icons: no cairosvg, System Settings' icons left to Breeze", file=sys.stderr)
        return
    if not os.path.isdir(f"{base}/preferences/32"):
        print(f"icons: no Breeze icons in {base}, System Settings' icons left to Breeze", file=sys.stderr)
        return
    names = sorted({f[:-4] for f in os.listdir(f"{base}/preferences/32") if f.endswith(".svg") and not f.endswith("-symbolic.svg")}
                   | set(SETTINGS_EXTRA))
    d = f"{out}/scalable/apps"
    done = {}
    for name in names:
        if name.startswith(SETTINGS_SKIP) or os.path.lexists(f"{d}/{name}.svg"):
            continue
        src = breeze_icon(base, name)
        if not src:
            continue
        key = (src, settings_color(name))
        if key in done:
            os.symlink(done[key] + ".svg", f"{d}/{name}.svg")
            continue
        open(f"{d}/{name}.svg", "w").write(duotone_tile(settings_color(name), src))
        done[key] = name


if __name__ == "__main__":
    out = sys.argv[1] + "/icons/DD-Party"
    logo_png = sys.argv[2]
    if os.path.exists(out):
        shutil.rmtree(out)
    write_set(f"{out}/scalable/places", PLACES, folder)
    write_set(f"{out}/scalable/places", {"user-trash": (RED, "trash"), "user-trash-full": (RED, "trash", "rainbow")}, tile)
    write_set(f"{out}/scalable/mimetypes", MIMES, filetype)
    write_set(f"{out}/scalable/devices", DEVICES, tile)
    write_set(f"{out}/scalable/apps", APPS, tile)
    write_settings(out)
    open(f"{out}/scalable/apps/start-here-kde.svg", "w").write(start_icon())
    for n in START_NAMES:
        if n != "start-here-kde":
            os.symlink("start-here-kde.svg", f"{out}/scalable/apps/{n}.svg")
    open(f"{out}/scalable/apps/deskdroid.svg", "w").write(logo(logo_png))
    for n in LOGO_NAMES:
        if n != "deskdroid":
            os.symlink("deskdroid.svg", f"{out}/scalable/apps/{n}.svg")
    os.makedirs(f"{out}/scalable/places", exist_ok=True)
    os.symlink("../apps/start-here-kde.svg", f"{out}/scalable/places/start-here-kde.svg")
    os.symlink("../apps/start-here-kde.svg", f"{out}/scalable/places/distributor-logo.svg")
    # The -symbolic names menus and panels ask for (Kickoff's categories...):
    # newer KDE Frameworks look for those exactly through the whole theme
    # chain (so Breeze Dark's won) before trying the plain name.
    for sub in ("apps", "places", "mimetypes", "devices"):
        d = f"{out}/scalable/{sub}"
        for f in sorted(os.listdir(d)):
            name = f[:-4]
            if f.endswith(".svg") and not name.endswith("-symbolic") and not os.path.lexists(f"{d}/{name}-symbolic.svg"):
                os.symlink(f, f"{d}/{name}-symbolic.svg")
    dirs = ["scalable/apps", "scalable/places", "scalable/mimetypes", "scalable/devices"]
    ctx = {"apps": "Applications", "places": "Places", "mimetypes": "MimeTypes", "devices": "Devices"}
    idx = ["[Icon Theme]", "Name=DD Party", "Comment=DeskDroid's party look: chamfered, rainbow-coded icons. Everything else comes from Breeze Dark.",
           "Inherits=breeze-dark,breeze,hicolor", "Example=folder", "DisplayDepth=32", "FollowsColorScheme=false",
           "DesktopDefault=48", "PanelDefault=32", "ToolbarDefault=22", "SmallDefault=16", "DialogDefault=32",
           "Directories=" + ",".join(dirs), ""]
    for d in dirs:
        idx += [f"[{d}]", "Size=64", "MinSize=16", "MaxSize=512", "Type=Scalable", f"Context={ctx[d.split('/')[1]]}", ""]
    open(f"{out}/index.theme", "w").write("\n".join(idx))
