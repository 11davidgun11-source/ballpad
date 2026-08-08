# DOCS/INDEX.md — Plans and findings

Living table of contents. Numbered for reading order.

> **Path note:** On macOS case-insensitive volumes, `docs/` and `DOCS/` are the same directory.

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

## Final status (2026-08-08)
Definition of Done is **green** on both the iPhone and iPad simulators
(M1-M14, see 15-validation-log.md). Touch controls, the ⋯ menu, resolution
scaling, save round-trip, and layout persistence all work. In-match is ~20 fps
(guest-CPU ceiling on the simulator; menus/boot are 60 fps). Known gaps and
tech debt are ranked in [09-open-questions.md](09-open-questions.md)
("Where the project is at").

Companion research index: [../ref/INDEX.md](../ref/INDEX.md)
