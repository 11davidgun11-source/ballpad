#!/usr/bin/env python3
"""Apply debug logging patches to the engine source for crash diagnosis.
Writes all output to a log file instead of stderr (iOS crash reports discard stderr).

Globals are defined in crashlog.c (C file, external linkage) and extern-declared
in main.cpp and feManager.cpp (C++ files). This avoids static linkage issues
and ensures the crash handler can always reach the log path."""
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

    print("=== Applying debug patches (file logging, v2) ===\n")

    # ════════════════════════════════════════════════════════════════════
    # crashlog.c: define globals + redirect crash handler to log file
    # ════════════════════════════════════════════════════════════════════

    # 1. Add includes and define globals right after existing includes, before the #if
    patch_file(crashlog,
        '#include <string.h>\n\n#if !defined(_WIN32)',
        '#include <string.h>\n#include <fcntl.h>\n#include <unistd.h>\n#include <stdio.h>\n\n'
        '/* Debug log globals — defined here with external linkage */\n'
        'char g_log_path[1024] = {0};\n'
        'int g_crash_log_fd = -1;\n'
        'FILE* g_debug_log = NULL;\n\n'
        '#if !defined(_WIN32)')

    # 2. In crash_handler: open log file and redirect output
    patch_file(crashlog,
        'static void crash_handler(int sig)\n{\n    // Async-signal-safe only:',
        '''static void crash_handler(int sig)
{
    // Open log file for appending (async-signal-safe open/write)
    int log_fd = -1;
    if (g_log_path[0] != '\\0')
        log_fd = open(g_log_path, O_WRONLY | O_APPEND, 0);
    int out_fd = (log_fd != -1) ? log_fd : 2;

    // Async-signal-safe only:''')

    # 3. Redirect the write calls from fd 2 to out_fd
    patch_file(crashlog,
        '    write(2, "\\n*** strikers: ", 15);\n    write(2, name, strlen(name));',
        '    write(out_fd, "\\n*** strikers: ", 15);\n    write(out_fd, name, strlen(name));')

    # 4. Redirect backtrace_symbols_fd
    patch_file(crashlog,
        '    backtrace_symbols_fd(frames, n, 2);',
        '    backtrace_symbols_fd(frames, n, out_fd);\n    if (log_fd != -1) { fsync(log_fd); close(log_fd); }')

    # ════════════════════════════════════════════════════════════════════
    # main.cpp: extern-declare globals, open log file in main()
    # ════════════════════════════════════════════════════════════════════

    # 1. Add includes after "types.h"
    patch_file(main_cpp,
        '#include "types.h"\n#include "NL/nlBind.h"',
        '#include "types.h"\n#include <cstdio>\n#include <cstdlib>\n#include <csignal>\n'
        '#include <execinfo.h>\n#include <fcntl.h>\n#include <unistd.h>\n'
        '#include "NL/nlBind.h"')

    # 2. Add extern declarations and log-open function before DoMemCheck
    patch_file(main_cpp,
        'static void DoMemCheck()\n{\n}',
        '/* Debug log globals — defined in crashlog.c */\n'
        'extern "C" {\n'
        'extern char g_log_path[1024];\n'
        'extern int g_crash_log_fd;\n'
        'extern FILE* g_debug_log;\n'
        '}\n\n'
        'static void OpenDebugLog() {\n'
        '    // Write to Documents/ (writable, visible in Files app on iOS)\n'
        '    // HOME is set by LiveContainer to the app\'s data container root\n'
        '    const char* home = getenv("HOME");\n'
        '    if (home != NULL && home[0] != \'\\0\')\n'
        '        snprintf(g_log_path, sizeof(g_log_path), "%s/Documents/ballpad-crash.log", home);\n'
        '    else\n'
        '        snprintf(g_log_path, sizeof(g_log_path), "/tmp/ballpad-crash.log");\n'
        '    g_crash_log_fd = open(g_log_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);\n'
        '    if (g_crash_log_fd >= 0) {\n'
        '        g_debug_log = fdopen(g_crash_log_fd, "w");\n'
        '        fprintf(g_debug_log, "[DEBUG] Log opened: %s\\n", g_log_path);\n'
        '        fflush(g_debug_log);\n'
        '    }\n'
        '}\n\n'
        'static void DoMemCheck()\n{\n}')

    # 3. Insert OpenDebugLog() call at the very start of main()
    patched_main = patch_file(main_cpp,
        'int main(int argc, char* argv[])\n{\n    // PORT: strikers.ini -> environment, before anything reads one.',
        'int main(int argc, char* argv[])\n{\n'
        '    OpenDebugLog();\n'
        '    // PORT: strikers.ini -> environment, before anything reads one.')

    if not patched_main:
        patch_file(main_cpp,
            'int main(int argc, char* argv[])\n{\n    // PORT: strikers.ini',
            'int main(int argc, char* argv[])\n{\n'
            '    OpenDebugLog();\n'
            '    // PORT: strikers.ini')

    # ════════════════════════════════════════════════════════════════════
    # feManager.cpp: extern-declare g_debug_log, redirect fprintf to file
    # ════════════════════════════════════════════════════════════════════

    # 1. Add extern declaration for g_debug_log
    patched = patch_file(fe_mgr,
        '#include "Game/FE/feManager.h"\n\n#include <cstdio>\n#include <cstdlib>\n#include <csignal>\n#include <execinfo.h>\n\n#include "Game/Camera/CameraMan.h"',
        '#include "Game/FE/feManager.h"\n\n#include <cstdio>\n#include <cstdlib>\n#include <csignal>\n#include <execinfo.h>\n\n'
        'extern "C" { extern FILE* g_debug_log; }\n'
        '#define DBG (g_debug_log ? g_debug_log : stderr)\n\n'
        '#include "Game/Camera/CameraMan.h"')

    if not patched:
        # Try variant without the extra includes (previous debug builds may have altered this)
        patch_file(fe_mgr,
            '#include "Game/FE/feManager.h"\n\n#include "Game/Camera/CameraMan.h"',
            '#include "Game/FE/feManager.h"\n\n'
            'extern "C" { extern FILE* g_debug_log; }\n'
            '#define DBG (g_debug_log ? g_debug_log : stderr)\n\n'
            '#include "Game/Camera/CameraMan.h"')

    # 2. Replace all fprintf(stderr with fprintf(DBG and fflush(stderr) with fflush(DBG
    for _ in range(20):
        patch_file(fe_mgr, 'fprintf(stderr,', 'fprintf(DBG,')
    patch_file(fe_mgr, 'fflush(stderr)', 'fflush(DBG)')

    print("\n=== Done ===")

    # Verify
    for name, path in [("feManager.cpp", fe_mgr), ("main.cpp", main_cpp), ("crashlog.c", crashlog)]:
        with open(path) as f:
            content = f.read()
        dbg_count = content.count("fprintf(DBG") + content.count("write(out_fd")
        print(f"  {name}: {dbg_count} debug output calls")

    with open(main_cpp) as f:
        if "OpenDebugLog" in f.read():
            print(f"  Log file path: <container>/Documents/ballpad-crash.log")

if __name__ == "__main__":
    main()
