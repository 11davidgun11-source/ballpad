#!/usr/bin/env python3
"""Apply debug logging patches to the engine source for crash diagnosis.
Writes all output to a log file instead of stderr (iOS crash reports discard stderr)."""
import sys, os

def patch_file(path, old, new):
    with open(path, 'r') as f:
        content = f.read()
    if old not in content:
        print(f"  WARNING: pattern not found in {os.path.basename(path)}:")
        print(f"    {old[:80]}...")
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

    print("=== Applying debug patches (file logging) ===\n")

    # ════════════════════════════════════════════════════════════════════
    # main.cpp: open log file, define globals, install crash handler
    # ════════════════════════════════════════════════════════════════════

    # 1. Add includes after "types.h"
    patch_file(main_cpp,
        '#include "types.h"\n#include "NL/nlBind.h"',
        '#include "types.h"\n#include <cstdio>\n#include <cstdlib>\n#include <csignal>\n#include <execinfo.h>\n#include <fcntl.h>\n#include <unistd.h>\n#include <mach-o/dyld.h>\n#include "NL/nlBind.h"')

    # 2. Add global log path and file handle BEFORE DoMemCheck
    patch_file(main_cpp,
        'static void DoMemCheck()\n{\n}',
        'static char g_log_path[1024];\nint g_crash_log_fd = -1;\nFILE* g_debug_log = nullptr;\n\nstatic void DoMemCheck()\n{\n}')

    # 3. Insert log file open at the very start of main(), before everything else
    # Find: "int main(int argc, char* argv[])\n{" then the first real code
    # The actual file has: int main(...) { \n    // PORT: strikers.ini
    # We try multiple patterns
    patched_main = patch_file(main_cpp,
        'int main(int argc, char* argv[])\n{\n    // PORT: strikers.ini -> environment, before anything reads one.',
        '''int main(int argc, char* argv[])
{
    // DEBUG: open log file next to the executable
    {
        char exe_dir[1024];
        uint32_t sz = sizeof(exe_dir);
        if (_NSGetExecutablePath(exe_dir, &sz) == 0) {
            char resolved[1024];
            if (realpath(exe_dir, resolved) != NULL) {
                char* slash = strrchr(resolved, '/');
                if (slash) *slash = '\\0';
                snprintf(g_log_path, sizeof(g_log_path), "%s/ballpad-crash.log", resolved);
            }
        }
        if (g_log_path[0] == '\\0')
            snprintf(g_log_path, sizeof(g_log_path), "/tmp/ballpad-crash.log");
        g_crash_log_fd = open(g_log_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (g_crash_log_fd >= 0) {
            g_debug_log = fdopen(g_crash_log_fd, "w");
            fprintf(g_debug_log, "[DEBUG] Log opened: %s\\n", g_log_path);
            fflush(g_debug_log);
        }
    }

    // PORT: strikers.ini -> environment, before anything reads one.''')

    if not patched_main:
        # Fallback: try the simpler pattern from the engine fork
        patch_file(main_cpp,
            'int main(int argc, char* argv[])\n{\n    // PORT: strikers.ini',
            '''int main(int argc, char* argv[])
{
    // DEBUG: open log file next to the executable
    {
        char exe_dir[1024];
        uint32_t sz = sizeof(exe_dir);
        if (_NSGetExecutablePath(exe_dir, &sz) == 0) {
            char resolved[1024];
            if (realpath(exe_dir, resolved) != NULL) {
                char* slash = strrchr(resolved, '/');
                if (slash) *slash = '\\0';
                snprintf(g_log_path, sizeof(g_log_path), "%s/ballpad-crash.log", resolved);
            }
        }
        if (g_log_path[0] == '\\0')
            snprintf(g_log_path, sizeof(g_log_path), "/tmp/ballpad-crash.log");
        g_crash_log_fd = open(g_log_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (g_crash_log_fd >= 0) {
            g_debug_log = fdopen(g_crash_log_fd, "w");
            fprintf(g_debug_log, "[DEBUG] Log opened: %s\\n", g_log_path);
            fflush(g_debug_log);
        }
    }

    // PORT: strikers.ini''')

    # ════════════════════════════════════════════════════════════════════
    # crashlog.c: redirect crash backtrace to log file
    # ════════════════════════════════════════════════════════════════════

    # 1. Add extern declaration and include after existing includes
    patch_file(crashlog,
        '#include <string.h>\n\n#if !defined(_WIN32)',
        '#include <string.h>\n#include <fcntl.h>\n#include <unistd.h>\n\nextern const char* g_log_path;\nextern int g_crash_log_fd;\n\n#if !defined(_WIN32)')

    # 2. In crash_handler: open log file and redirect output
    patch_file(crashlog,
        'static void crash_handler(int sig)\n{\n    // Async-signal-safe only:',
        '''static void crash_handler(int sig)
{
    // Open log file for appending (async-signal-safe open/write)
    int log_fd = -1;
    if (g_log_path != NULL && g_log_path[0] != '\\0')
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
    # feManager.cpp: write debug trace to g_debug_log instead of stderr
    # ════════════════════════════════════════════════════════════════════

    # 1. Add extern declaration for g_debug_log
    patch_file(fe_mgr,
        '#include "Game/FE/feManager.h"\n\n#include <cstdio>\n#include <cstdlib>\n#include <csignal>\n#include <execinfo.h>\n\n#include "Game/Camera/CameraMan.h"',
        '#include "Game/FE/feManager.h"\n\n#include <cstdio>\n#include <cstdlib>\n#include <csignal>\n#include <execinfo.h>\n\nextern FILE* g_debug_log;\n#define DBG (g_debug_log ? g_debug_log : stderr)\n\n#include "Game/Camera/CameraMan.h"')

    # Also add the extern if the first pattern (with DBG macro) didn't match
    # because the previous debug-patch may have already added the includes
    patch_file(fe_mgr,
        '#include "Game/FE/feManager.h"\n\n#include <cstdio>\n#include <cstdlib>\n#include <csignal>\n#include <execinfo.h>\n\n#include "Game/Camera/CameraMan.h"',
        '#include "Game/FE/feManager.h"\n\n#include <cstdio>\n#include <cstdlib>\n#include <csignal>\n#include <execinfo.h>\n\nextern FILE* g_debug_log;\n#define DBG (g_debug_log ? g_debug_log : stderr)\n\n#include "Game/Camera/CameraMan.h"')

    # 2. Replace all fprintf(stderr with fprintf(DBG and fflush(stderr) with fflush(DBG
    patch_file(fe_mgr, 'fprintf(stderr,', 'fprintf(DBG,')
    patch_file(fe_mgr, 'fprintf(stderr,', 'fprintf(DBG,')
    patch_file(fe_mgr, 'fprintf(stderr,', 'fprintf(DBG,')
    patch_file(fe_mgr, 'fprintf(stderr,', 'fprintf(DBG,')
    patch_file(fe_mgr, 'fprintf(stderr,', 'fprintf(DBG,')
    patch_file(fe_mgr, 'fprintf(stderr,', 'fprintf(DBG,')
    patch_file(fe_mgr, 'fprintf(stderr,', 'fprintf(DBG,')
    patch_file(fe_mgr, 'fprintf(stderr,', 'fprintf(DBG,')
    patch_file(fe_mgr, 'fprintf(stderr,', 'fprintf(DBG,')
    patch_file(fe_mgr, 'fprintf(stderr,', 'fprintf(DBG,')
    patch_file(fe_mgr, 'fprintf(stderr,', 'fprintf(DBG,')
    patch_file(fe_mgr, 'fprintf(stderr,', 'fprintf(DBG,')
    patch_file(fe_mgr, 'fprintf(stderr,', 'fprintf(DBG,')
    patch_file(fe_mgr, 'fprintf(stderr,', 'fprintf(DBG,')
    patch_file(fe_mgr, 'fprintf(stderr,', 'fprintf(DBG,')
    patch_file(fe_mgr, 'fflush(stderr)', 'fflush(DBG)')

    print("\n=== Done ===")
    # Verify
    for name, path in [("feManager.cpp", fe_mgr), ("main.cpp", main_cpp), ("crashlog.c", crashlog)]:
        with open(path) as f:
            content = f.read()
        dbg_count = content.count("fprintf(DBG") + content.count("write(out_fd")
        print(f"  {name}: {dbg_count} debug output calls")

    # Check log path
    with open(main_cpp) as f:
        if "g_log_path" in f.read():
            print(f"  Log file path: <executable_dir>/ballpad-crash.log")

if __name__ == "__main__":
    main()
