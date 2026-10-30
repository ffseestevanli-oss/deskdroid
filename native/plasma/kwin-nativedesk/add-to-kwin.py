#!/usr/bin/env python3
"""Adds the nativedesk backend to a KWin source tree: copies the backend in as
src/backends/nativedesk and gives kwin_wayland a --nativedesk option."""
import pathlib
import shutil
import sys

here = pathlib.Path(__file__).resolve().parent
kwin = pathlib.Path(sys.argv[1])

dest = kwin / "src/backends/nativedesk"
dest.mkdir(parents=True, exist_ok=True)
for f in ("CMakeLists.txt", "nativedesk_backend.h", "nativedesk_backend.cpp"):
    shutil.copy(here / f, dest / f)
shutil.copy(here.parent.parent / "nativedesk/protocol.h", dest / "protocol.h")


def edit(path, old, new):
    p = kwin / path
    s = p.read_text()
    if s.count(old) != 1:
        sys.exit(f"{path}: expected one '{old.strip()}'")
    p.write_text(s.replace(old, new))


edit("src/backends/CMakeLists.txt", "add_subdirectory(virtual)", "add_subdirectory(virtual)\nadd_subdirectory(nativedesk)")
m = "src/main_wayland.cpp"
edit(m, '#include "backends/virtual/virtual_backend.h"\n',
     '#include "backends/virtual/virtual_backend.h"\n#include "backends/nativedesk/nativedesk_backend.h"\n')
edit(m, "    parser.addOption(virtualFbOption);\n",
     "    parser.addOption(virtualFbOption);\n"
     "    QCommandLineOption nativeDeskOption(QStringLiteral(\"nativedesk\"), QStringLiteral(\"Show the desktop on DeskDroid's Android compositor.\"));\n"
     "    parser.addOption(nativeDeskOption);\n")
edit(m, "        Virtual,\n    };", "        Virtual,\n        NativeDesk,\n    };")
edit(m, "    } else if (parser.isSet(virtualFbOption)) {\n",
     "    } else if (parser.isSet(nativeDeskOption)) {\n"
     "        backendType = BackendType::NativeDesk;\n"
     "    } else if (parser.isSet(virtualFbOption)) {\n")
edit(m, "    case BackendType::Virtual: {\n",
     "    case BackendType::NativeDesk:\n"
     "        a.setSession(KWin::Session::create(KWin::Session::Type::Noop));\n"
     "        a.setOutputBackend(std::make_unique<KWin::NativeDeskBackend>(initialWindowSize, outputScale));\n"
     "        break;\n"
     "    case BackendType::Virtual: {\n")
