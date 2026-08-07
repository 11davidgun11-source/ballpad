# 08 — BOT2_PROMPT checklist audit

| # | Requirement | Present |
|---|-------------|---------|
| 1 | Identity and repo context (ref/, DOCS/) | yes — BOT2 §1 + links to 10/11 |
| 2 | Build/test loop with gates from DOCS/07 | yes — BOT2 §2 + 07 execution bible |
| 3 | Single-simulator mutex + shutdown-before-boot | yes — BOT2 §2 + DOCS/03 + sim_mutex contract |
| 4 | Gated checks / self-verify with proofs | yes — BOT2 §4 + DOCS/12 |
| 5 | Touch-control mandate DOCS/05 from scratch | yes — BOT2 §5 |
| 6 | Menu mandate DOCS/06 | yes — BOT2 §6 |
| 7 | Definition of done phone+pad | yes — BOT2 §7 + DOCS/12 must-pass |
| 8 | Discipline rules | yes — BOT2 §8 |

## Hardening extras (post Phase 1)
- Exact generate/build commands with path pins
- Path S vs C decision table and fallbacks
- PAD bit table and `ballpad_pad.h` contract
- Failure matrix in DOCS/09
- Progress board + proof naming convention
- Timeboxes per step
- Target tree layout for first-party code

Gate G8: PASS (hardened)
