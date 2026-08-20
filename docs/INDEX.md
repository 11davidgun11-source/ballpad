# DOCS/INDEX.md — Plans and findings

Living table of contents. Numbered for reading order.

> **Path note:** On macOS case-insensitive volumes, `docs/` and `DOCS/` are the same directory.

## Current planning authority (2026-08-19)

| Doc | Title |
|-----|-------|
| [28-decomp-integration-plan-2026-08-19.md](28-decomp-integration-plan-2026-08-19.md) | **Current decision: verified decomp build contract, source-aware runtime, and scene-driven autostart** |
| [BOT6_DECOMP_INTEGRATION_LOOP.md](BOT6_DECOMP_INTEGRATION_LOOP.md) | **The only next-agent prompt: exact C0–C6 implementation loop** |
| [29-decomp-runtime-crosswalk.md](29-decomp-runtime-crosswalk.md) | Pinned identity, seed source/runtime map, package scoreboard, and evidence template |
| [27-graphics-repair-runbook-2026-08-19.md](27-graphics-repair-runbook-2026-08-19.md) | Verification reference integrated into doc 28; no longer the top-level work order |
| [BOT5_GRAPHICS_REPAIR_LOOP.md](BOT5_GRAPHICS_REPAIR_LOOP.md) | Superseded graphics-only agent loop; retained for history |
| [26-quickboot-graphics-investigation-2026-08-19.md](26-quickboot-graphics-investigation-2026-08-19.md) | Evidence-backed QuickBoot feasibility, root-cause ranking, and parity design |
| [24-technical-audit-2026-08-19.md](24-technical-audit-2026-08-19.md) | Broader technical audit, reproducibility work, and release exit gates |
| [25-next-agent-graphics-investigation-brief.md](25-next-agent-graphics-investigation-brief.md) | Completed investigation brief; retained as the assignment record, not the next action |
| [23-goal-loop-2026-08-18.md](23-goal-loop-2026-08-18.md) | Current renderer/Simulator baseline and the evidence-based operating loop |
| [15-validation-log.md](15-validation-log.md) | Dated validation evidence; not a release sign-off |

Documents 00–22 are retained for research and history. In particular,
[22-graphics-handoff-2026-08-10.md](22-graphics-handoff-2026-08-10.md) is a
useful renderer handoff, but it is no longer the planning authority.

Start with the root [`README.md`](../README.md) for setup and user-facing
status, then read document 28 and the Bot 6 loop for current execution
authority. Documents 27 and 26 supply existing graphics and QuickBoot evidence;
document 24 remains the broader release audit.

## Start here (Bot 2)
1. [BOT2_LAUNCH_PROMPT.md](BOT2_LAUNCH_PROMPT.md) — **paste this into a new chat**
2. [BOT2_PROMPT.md](BOT2_PROMPT.md) — short pointer
2. [10-bot2-operating-manual.md](10-bot2-operating-manual.md) — daily runbook
3. [11-target-repo-layout.md](11-target-repo-layout.md) — files to create
4. [07-build-plan.md](07-build-plan.md) — gated steps 0–15 (execution bible)
5. [12-acceptance-proofs.md](12-acceptance-proofs.md) — Definition of Done scoreboard

## Phase 1 research and specs
| Doc | Title | Status |
|-----|-------|--------|
| [00-phase1-charter.md](00-phase1-charter.md) | Phase 1 charter | complete |
| [01-foundation-map.md](01-foundation-map.md) | Foundation map (G1) | complete |
| [02-native-path.md](02-native-path.md) | macOS→ARM64→iOS path (G2) | complete + Bot2 decisions |
| [03-simulator-harness.md](03-simulator-harness.md) | Simulator mutex and commands (G3) | complete |
| [04-touch-controls-research.md](04-touch-controls-research.md) | Touch front-end research (G4) | complete |
| [05-touch-control-spec.md](05-touch-control-spec.md) | Touch UX product spec (G5) | complete |
| [06-menu-spec.md](06-menu-spec.md) | ⋯ menu spec (G6) | complete |
| [07-build-plan.md](07-build-plan.md) | Gated build plan (G7) | **hardened** |
| [08-bot2-checklist-audit.md](08-bot2-checklist-audit.md) | BOT2 prompt checklist audit | complete |
| [09-open-questions.md](09-open-questions.md) | Risks, fallbacks, failure matrix | living |
| [10-bot2-operating-manual.md](10-bot2-operating-manual.md) | Operating manual | complete |
| [11-target-repo-layout.md](11-target-repo-layout.md) | Target repo layout + PAD ABI | complete |
| [12-acceptance-proofs.md](12-acceptance-proofs.md) | Acceptance proofs / DoD | complete |
| [BOT2_PROMPT.md](BOT2_PROMPT.md) | Build-agent goal loop (G8) | **hardened** |

## Produced by Bot 2 during execution
| Doc | Title |
|-----|-------|
| [15-validation-log.md](15-validation-log.md) | **Final scoreboard — DoD green on phone + iPad** |
| `build/proofs/PROGRESS.md` | Live step tracker (gitignored build tree) |

## Post-DoD review (2026-08-08)
| Doc | Title |
|-----|-------|
| [20-review-and-next-steps.md](20-review-and-next-steps.md) | **Independent review: ranked issues, original-agent mistakes, phase plan (start here)** |
| [BOT4_LAUNCH_PROMPT.md](BOT4_LAUNCH_PROMPT.md) | **Next agent goal loop: performance, UI, usability — paste into a new chat** |

## Historical status note

The 2026-08-08 Definition-of-Done record is retained in
[15-validation-log.md](15-validation-log.md), but later renderer and
physical-device findings qualify it. Do not treat the historical Simulator
green status as release readiness; use the current dashboard in document 24.

Companion research index: [../ref/INDEX.md](../ref/INDEX.md)
