# Native Strikers execution ledger

## Current state

Planning package prepared; implementation has not started. No Simulator/native-engine acceptance is claimed.

- Workspace: `/Users/chrissotraidis/GitHub/ballpad`
- Upstream: `https://github.com/new-coke/strikers`
- Initial pin: `22649cb12c112454a34217429296c95bb181af8a`
- Authority: docs 33, 34, 35 and `BOT7_NATIVE_STRIKERS_LOOP.md`
- Active phase: N0
- Next action: record protected working-tree state, acquire persistent local native fork, verify toolchain and existing local game data.
- Goal ID/status: not created by documentation task; implementation agent records if available.

## Phase board

| Phase | Status | Evidence / blocker |
|---|---|---|
| N0 Protected baseline | NOT_RUN | |
| N1 Native desktop baseline | NOT_RUN | |
| N2 Mobile builds and dependencies | NOT_RUN | |
| N3 Complete native Simulator match | NOT_RUN | |
| N4 Ballpad interface integration | NOT_RUN | |
| N5 Audio, saves and lifecycle | NOT_RUN | |
| N6 Performance/render/endurance | NOT_RUN | |
| N7 Clean reproduction and handoff | NOT_RUN | |
| Physical device validation | NOT_RUN | Outside Simulator completion; hardware evidence required |
| Public distribution clearance | NOT_RUN | Separate rights/release decision |

## Required living sections

The implementation agent fills these sections with concise, attributable facts, preserving prior failures when superseded:

1. Protected files and baseline SHAs/status; working branches and upstream remote.
2. Dependency manifest path, patch digest, platform toolchain versions and clean-bootstrap command.
3. Local data identity (no game bytes), test copies and save backup locations.
4. Bridge architecture, frame/main-thread ownership, supported lifecycle transitions and configuration semantics.
5. Phone/iPad test matrix for every F/B row in doc 34; per-run metadata, exact commands and exit results.
6. Timing/memory/audio summary by scene and build; never relabel step time as frame rate.
7. Attribution/asset audit and bundled notice verification.
8. Hypothesis log: failure, observation, smallest change, before/after evidence and remaining uncertainty.
9. Command mapping if the implementation changes the proposed script names.
10. Final artifacts, unsigned-device build, clean-reproduction proof and explicit device/distribution limitations.

## Checkpoint template

```text
Phase / gate:
Date / build identity / patch digest:
Source invariant and observed failure:
Hypothesis:
Change:
Command / exit status:
Runtime scene / duration / device-or-Simulator:
Evidence bundle:
Result: PASS | FAIL | BLOCKED | NOT_RUN
What this result does and does not prove:
Next concrete action:
```

Update the current-state section and next action at every meaningful checkpoint so another agent can resume without replaying completed work. A summary is not a substitute for the evidence bundle, and missing temporary research logs do not prevent a fresh verified baseline.
