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

print("deskdroid changes: applied")
