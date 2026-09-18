#!/usr/bin/env python3
"""Apply debug logging patches to the engine source for crash diagnosis."""
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

    for p in [fe_mgr, main_cpp]:
        if not os.path.isfile(p):
            print(f"ERROR: {p} not found")
            sys.exit(1)

    print("=== Applying debug patches ===\n")

    # ── feManager.cpp ──

    # 1. Add logging includes after existing include
    patch_file(fe_mgr,
        '#include "Game/FE/feManager.h"\n\n#include "Game/Camera/CameraMan.h"',
        '#include "Game/FE/feManager.h"\n\n#include <cstdio>\n#include <cstdlib>\n#include <csignal>\n#include <execinfo.h>\n\n#include "Game/Camera/CameraMan.h"')

    # 2. Log ExitWinnerScreen entry
    patch_file(fe_mgr,
        'void FrontEnd::ExitWinnerScreen()\n{\n    cCameraManager::PopCameraWithTransition',
        'void FrontEnd::ExitWinnerScreen()\n{\n    fprintf(stderr, "[DEBUG] === ExitWinnerScreen START ===\\n");\n    fprintf(stderr, "[DEBUG] feState: current=%d pending=%d previous=%d\\n", (int)m_feStateCurrent, (int)m_feStatePending, (int)m_feStatePrevious);\n    fprintf(stderr, "[DEBUG] m_pPauseMenuCamera=%p g_AllActorsHidden=%.2f\\n", (void*)m_pPauseMenuCamera, (double)g_AllActorsHidden);\n    fprintf(stderr, "[DEBUG] taskManager: CurrState=%d PendingState=%d\\n", nlTaskManager::m_pInstance->m_CurrState, nlTaskManager::m_pInstance->m_PendingState);\n    fflush(stderr);\n\n    cCameraManager::PopCameraWithTransition')

    # 3. Log after SetNextState(2) in ExitWinnerScreen
    patch_file(fe_mgr,
        '    nlTaskManager::SetNextState(2);\n}',
        '    nlTaskManager::SetNextState(2);\n\n    fprintf(stderr, "[DEBUG] SetNextState(2) done -> new PendingState=%d\\n", nlTaskManager::m_pInstance->m_PendingState);\n    fprintf(stderr, "[DEBUG] === ExitWinnerScreen END ===\\n");\n    fflush(stderr);\n}')

    # 4. Log FEEventHandler event 3 (match over)
    patch_file(fe_mgr,
        '    case 3:\n        OSReport("[match] over score=%d-%d\\n",',
        '    case 3:\n        fprintf(stderr, "[DEBUG] FEEvent: match over (event 3)\\n");\n        fflush(stderr);\n        OSReport("[match] over score=%d-%d\\n",')

    # 5. Log FrontEnd::Update state at entry
    patch_file(fe_mgr,
        'void FrontEnd::Update(float fTimeDelta)\n{\n    m_pauseDelay -= fTimeDelta;',
        'void FrontEnd::Update(float fTimeDelta)\n{\n    fprintf(stderr, "[DBG-FE] Upd dt=%.3f st=%d pend=%d prev=%d task=(%d,%d)\\n", (double)fTimeDelta, (int)m_feStateCurrent, (int)m_feStatePending, (int)m_feStatePrevious, (int)nlTaskManager::m_pInstance->m_CurrState, (int)nlTaskManager::m_pInstance->m_PendingState);\n    fflush(stderr);\n\n    m_pauseDelay -= fTimeDelta;')

    # 6. Log state 5 (END_GAME) entry
    patch_file(fe_mgr,
        '    case 5:\n    {\n        nlTaskManager::SetNextState(1);',
        '    case 5:\n    {\n        fprintf(stderr, "[DBG-FE] case 5: END_GAME -> SetNextState(1)\\n");\n        fflush(stderr);\n        nlTaskManager::SetNextState(1);')

    # 7. Log state 3 (pre-game)
    patch_file(fe_mgr,
        '    case 3:\n    {\n        BaseSceneHandler* scene;',
        '    case 3:\n    {\n        fprintf(stderr, "[DBG-FE] case 3: PRE_GAME_START\\n");\n        fflush(stderr);\n        BaseSceneHandler* scene;')

    # 8. Log state 8 (wait user input)
    patch_file(fe_mgr,
        '    case 8:\n        if (nlTaskManager::m_pInstance->m_CurrState == 1)',
        '    case 8:\n        fprintf(stderr, "[DBG-FE] case 8: WAIT_USER_END_GAME\\n");\n        fflush(stderr);\n        if (nlTaskManager::m_pInstance->m_CurrState == 1)')

    # ── main.cpp ──

    # 1. Add includes
    patch_file(main_cpp,
        '#include "types.h"\n#include "NL/nlBind.h"',
        '#include "types.h"\n#include <cstdio>\n#include <cstdlib>\n#include <csignal>\n#include <execinfo.h>\n#include "NL/nlBind.h"')

    # 2. Insert SIGABRT handler before main()
    patch_file(main_cpp,
        'static void DoMemCheck()\n{\n}\n\n/**',
        'static void debug_abort_handler(int sig)\n{\n    fprintf(stderr, "\\n=== CRASH CAUGHT (signal %d) ===\\n", sig);\n    fflush(stderr);\n    void* callstack[64];\n    int n = backtrace(callstack, 64);\n    char** syms = backtrace_symbols(callstack, n);\n    if (syms) {\n        for (int i = 0; i < n; i++)\n            fprintf(stderr, "  [%d] %s\\n", i, syms[i]);\n        free(syms);\n    }\n    fprintf(stderr, "=== END BACKTRACE ===\\n");\n    fflush(stderr);\n    signal(sig, SIG_DFL);\n    raise(sig);\n}\n\n/**')

    # 3. Install signal handlers at top of main()
    patch_file(main_cpp,
        'int main(int argc, char* argv[])\n{\n    // PORT: strikers.ini',
        'int main(int argc, char* argv[])\n{\n    signal(SIGABRT, debug_abort_handler);\n    fprintf(stderr, "[DEBUG] SIGABRT handler installed\\n");\n    fflush(stderr);\n\n    // PORT: strikers.ini')

    print("\n=== Done ===")
    # Verify
    for name, path in [("feManager.cpp", fe_mgr), ("main.cpp", main_cpp)]:
        with open(path) as f:
            count = f.read().count("fprintf(stderr")
        print(f"  {name}: {count} fprintf(stderr) calls added")

if __name__ == "__main__":
    main()
