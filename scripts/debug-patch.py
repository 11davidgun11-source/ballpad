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

    print("=== Applying debug patches (BallpadLogFmt, v4) ===\n")

    # ════════════════════════════════════════════════════════════════════
    # main.cpp: add BallpadLogFmt extern declaration
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
    # feManager.cpp: replace fprintf(stderr,...) with BallpadLogFmt(...)
    # Direct replacement — no macros, no conflicts with msl/printf.h
    # ════════════════════════════════════════════════════════════════════

    # 1. Add BallpadLogFmt extern declaration after existing includes
    patched = patch_file(fe_mgr,
        '#include "Game/FE/feManager.h"\n\n#include <cstdio>\n#include <cstdlib>\n#include <csignal>\n#include <execinfo.h>\n\n#include "Game/Camera/CameraMan.h"',
        '#include "Game/FE/feManager.h"\n\n#include <cstdio>\n#include <cstdlib>\n#include <csignal>\n#include <execinfo.h>\n\n'
        'extern "C" void BallpadLogFmt(const char *fmt, ...);\n\n'
        '#include "Game/Camera/CameraMan.h"')

    if not patched:
        # Try variant without the extra includes
        patch_file(fe_mgr,
            '#include "Game/FE/feManager.h"\n\n#include "Game/Camera/CameraMan.h"',
            '#include "Game/FE/feManager.h"\n\n'
            'extern "C" void BallpadLogFmt(const char *fmt, ...);\n\n'
            '#include "Game/Camera/CameraMan.h"')

    # 2. Replace all fprintf(stderr, with BallpadLogFmt( — up to 20 occurrences
    count = 0
    for _ in range(20):
        if patch_file(fe_mgr, 'fprintf(stderr,', 'BallpadLogFmt('):
            count += 1

    # 3. Remove fflush(stderr) calls (nothing to flush with BallpadLogFmt)
    patch_file(fe_mgr, '    fflush(stderr);', '')

    print(f"\n=== Done ===")
    print(f"  feManager.cpp: replaced {count} fprintf(stderr) calls with BallpadLogFmt")
    print(f"  Engine debug output → Documents/BallpadLogs/runtime.log")
    print(f"  Crash backtrace → iOS crash report (stderr)")

if __name__ == "__main__":
    main()
