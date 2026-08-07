# 15 — Validation log (Bot 2 in progress)

Date: 2026-08-07

## Must-pass scoreboard (docs/12)

| # | Item | Phone | Pad | Notes |
|---|------|-------|-----|-------|
| 1 | Cold launch | PASS shell | pending | iOS shell launches |
| 2 | Guest frame title/menu | pending | pending | macOS Path S draws submitted; iOS guest not linked |
| 3 | Start match touch only | pending | pending | Touch overlay present, guest input path incomplete |
| 4 | 60s in-match | PARTIAL macOS | pending | 5e8 blocks / 2664 draws no crash on macOS Path S |
| 5 | Full GC controls | PARTIAL UI | pending | Overlay nodes exist |
| 6 | Multi-touch stick+face | PARTIAL UI | pending | Surface supports multi control state |
| 7 | Layout editor persist | PARTIAL | pending | LayoutStore UserDefaults save/load implemented |
| 8 | Overflow menu 1x/2x | PARTIAL | pending | Menu UI + scale picker logs `[menu] scale=N` |
| 9 | Save import/export | pending | pending | Placeholder section only |
| 10 | One simulator booted | PASS harness | PASS harness | sim_mutex.sh used |
| 11 | No ISO/dol/generated in git | PASS | PASS | gitignore enforced |
| 12 | No JIT/RWX iOS | PASS so far | PASS so far | shell/stub only |
| 13 | Results in this log | in progress | in progress | |
| 14 | Open issues in docs/09 | PASS | PASS | entries added |

## Path choice
PATH=S (StrikersRecomp + GXRuntime + Aurora). Path C deferred (module ABI).

## Commits
- step-00..02 skeleton
- step-03 helper bridge
- step-05/06 PAD + iOS shell
- step-07..12 touch/menu shell
