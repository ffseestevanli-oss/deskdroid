#!/usr/bin/env python3
"""DeskDroid's own changes to Firefox, on top of Termux's (termux-patches/),
for what Termux does differently: Termux has PulseAudio, DeskDroid plays
sound through Android itself (AAudio, as GeckoView does).

    deskdroid.py <firefox source dir>
"""
import pathlib
import sys

src = pathlib.Path(sys.argv[1])


def edit(path, old, new, count=1):
    p = src / path
    s = p.read_text()
    if s.count(old) != count:
        sys.exit(f"{path}: expected {count} of {old.strip()[:80]!r}, found {s.count(old)}")
    p.write_text(s.replace(old, new))


# Sound: AAudio, Android's own audio API, which cubeb (Firefox's audio
# library) has a backend for. Upstream allows it only with GeckoView.
edit("toolkit/moz.configure",
     '    if any("aaudio" in value for value in values) and target.os != "Android":\n',
     '    if any("aaudio" in value for value in values) and target.kernel != "Linux":  # DeskDroid: Bionic\n')
# cubeb asks GeckoView's Java side for the Android context, only to tell the
# output latency; without one it reports "not supported", as its docs say.
(src / "media/libcubeb/src/cubeb-jni-instances.h").write_text("""\
#ifndef _CUBEB_JNI_INSTANCES_H_
#define _CUBEB_JNI_INSTANCES_H_
// DeskDroid: no GeckoView, so no Java context: cubeb's JNI parts say
// "not supported" (stream position falls back to its own clock).
#include <jni.h>
JNIEnv *cubeb_get_jni_env_for_thread() { return nullptr; }
jobject cubeb_jni_get_context_instance() { return nullptr; }
#endif
""")

# Wayland only and no D-Bus (as Termux): Gecko's "remote" (opening a link in
# the running browser) then falls back to its X11 version. Leave that out:
# a second start opens its own window instead of reusing the first.
R = "toolkit/components/remote/"
edit(R + "moz.build",
     '    else:\n        SOURCES += [\n            "nsGTKRemoteServer.cpp",',
     '    elif CONFIG["MOZ_X11"]:  # DeskDroid\n        SOURCES += [\n            "nsGTKRemoteServer.cpp",')
edit(R + "nsRemoteService.cpp",
     '#  else\n#    include "nsGTKRemoteServer.h"',
     '#  elif defined(MOZ_X11)  // DeskDroid\n#    include "nsGTKRemoteServer.h"')
edit(R + "nsRemoteService.cpp",
     '#  else\n  client = MakeUnique<nsXRemoteClient>(mStartupToken);\n#  endif',
     '#  elif defined(MOZ_X11)\n  client = MakeUnique<nsXRemoteClient>(mStartupToken);\n#  else\n  return NS_ERROR_NOT_AVAILABLE;\n#  endif')
edit(R + "nsRemoteService.cpp",
     '#  else\n  mRemoteServer = MakeUnique<nsGTKRemoteServer>();\n#  endif',
     '#  elif defined(MOZ_X11)\n  mRemoteServer = MakeUnique<nsGTKRemoteServer>();\n#  else\n  return;\n#  endif')

# Android runs programs only from the APK's library folder, so Firefox's
# program is a link in its own folder to a file there, and /proc/self/exe
# names the library folder. bin/firefox (native/nativedesk/firefox.sh) says
# where the link is; Firefox finds its files next to it, and starts its child
# processes through it.
edit("xpcom/build/BinaryPath.h",
     "#elif defined(XP_UNIX)\n#  include <stdlib.h>\n",
     "#elif defined(XP_UNIX)\n#  include <stdio.h>  // DeskDroid: snprintf\n#  include <stdlib.h>\n")
edit("xpcom/build/BinaryPath.h",
     """    ssize_t len = readlink(path, aResult, MAXPATHLEN - 1);
    if (len < 0) {
      return NS_ERROR_FAILURE;
    }
""",
     """    if (const char* deskdroid = getenv("DESKDROID_FIREFOX_BINARY")) {  // DeskDroid
      snprintf(aResult, MAXPATHLEN, "%s", deskdroid);
      return NS_OK;
    }
    ssize_t len = readlink(path, aResult, MAXPATHLEN - 1);
    if (len < 0) {
      return NS_ERROR_FAILURE;
    }
""")

print("deskdroid changes: applied")
