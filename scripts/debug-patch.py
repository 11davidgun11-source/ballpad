#!/usr/bin/env python3
"""Apply debug logging patches to the engine source for crash diagnosis.
Routes all engine debug output through BallpadLogFmt() which writes into
the existing Documents/BallpadLogs/runtime.log (proven to work on device).

The crash handler writes its backtrace to stderr (fd 2) which appears in
the iOS crash report."""
import sys, os

def patch_file(path, old, new):
    with open(path, 'r') as f:
        content = f.read()
    if old not in content:
        print(f"  WARNING: pattern not found in {os.path.basename(path)}:")
        for line in old.split('\n')[:3]:
            print(f"    {line[:100]}")
        return False
    content = content.replace(old, new, 1)
    with open(path, 'w') as f:
        f.write(content)
    print(f"  OK: patched {os.path.basename(path)}")
    return True

def main():
    engine = os.path.join("work", "native", "strikers")
    port = os.path.join(engine, "smstrikers-port")
    fe_mgr = os.path.join(port, "src", "Game", "FE", "feManager.cpp")
    main_cpp = os.path.join(port, "src", "Game", "main.cpp")
    crashlog = os.path.join(port, "src", "platform", "crashlog.c")

    for p in [fe_mgr, main_cpp, crashlog]:
        if not os.path.isfile(p):
            print(f"ERROR: {p} not found")
            sys.exit(1)

    print("=== Applying debug patches (BallpadLogFmt, v3) ===\n")

    # ════════════════════════════════════════════════════════════════════
    # crashlog.c: no changes needed — crash handler writes to stderr (fd 2)
    # which appears in the iOS crash report with backtrace_symbols output.
    # ════════════════════════════════════════════════════════════════════

    # ════════════════════════════════════════════════════════════════════
    # main.cpp: add BallpadLogFmt extern declaration + BallpadLog header
    # ════════════════════════════════════════════════════════════════════

    # 1. Add includes after "types.h"
    patch_file(main_cpp,
        '#include "types.h"\n#include "NL/nlBind.h"',
        '#include "types.h"\n#include <cstdio>\n#include <cstdlib>\n#include <csignal>\n'
        '#include <execinfo.h>\n#include <fcntl.h>\n#include <unistd.h>\n#include <sys/stat.h>\n'
        '#include "NL/nlBind.h"')

    # 2. Add BallpadLogFmt extern declaration before DoMemCheck
    patch_file(main_cpp,
        'static void DoMemCheck()\n{\n}',
        '/* Debug: route engine output through BallpadLogFmt → runtime.log */\n'
        'extern "C" void BallpadLogFmt(const char *fmt, ...);\n\n'
        'static void DoMemCheck()\n{\n}')

    # ════════════════════════════════════════════════════════════════════
    # feManager.cpp: redirect all fprintf(stderr,...) to BallpadLogFmt(...)
    # ════════════════════════════════════════════════════════════════════

    # 1. Add BallpadLogFmt extern + redirect macros after includes
    patched = patch_file(fe_mgr,
        '#include "Game/FE/feManager.h"\n\n#include <cstdio>\n#include <cstdlib>\n#include <csignal>\n#include <execinfo.h>\n\n#include "Game/Camera/CameraMan.h"',
        '#include "Game/FE/feManager.h"\n\n#include <cstdio>\n#include <cstdlib>\n#include <csignal>\n#include <execinfo.h>\n\n'
        'extern "C" void BallpadLogFmt(const char *fmt, ...);\n'
        '/* Redirect fprintf(stderr,...) to BallpadLogFmt → runtime.log */\n'
        '#define fprintf(stream, ...) BallpadLogFmt(__VA_ARGS__)\n'
        '#define fflush(stream)\n\n'
        '#include "Game/Camera/CameraMan.h"')

    if not patched:
        # Try variant without the extra includes
        patch_file(fe_mgr,
            '#include "Game/FE/feManager.h"\n\n#include "Game/Camera/CameraMan.h"',
            '#include "Game/FE/feManager.h"\n\n'
            'extern "C" void BallpadLogFmt(const char *fmt, ...);\n'
            '/* Redirect fprintf(stderr,...) to BallpadLogFmt → runtime.log */\n'
            '#define fprintf(stream, ...) BallpadLogFmt(__VA_ARGS__)\n'
            '#define fflush(stream)\n\n'
            '#include "Game/Camera/CameraMan.h"')

    # 2. No need to replace fprintf calls — the #define handles it

    print("\n=== Done ===")

    # Verify
    for name, path in [("feManager.cpp", fe_mgr), ("main.cpp", main_cpp), ("crashlog.c", crashlog)]:
        with open(path) as f:
            content = f.read()
        if name == "feManager.cpp":
            count = content.count("BallpadLogFmt") + content.count("#define fprintf")
            print(f"  {name}: {count} BallpadLogFmt references")
        elif name == "main.cpp":
            count = content.count("BallpadLogFmt")
            print(f"  {name}: {count} BallpadLogFmt references")
        else:
            print(f"  {name}: unmodified (crash handler writes to stderr)")

    print(f"\n  Engine debug output → Documents/BallpadLogs/runtime.log")
    print(f"  Crash backtrace → iOS crash report (stderr)")

if __name__ == "__main__":
    main()
