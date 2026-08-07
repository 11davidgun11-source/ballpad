# 12 — Acceptance proofs and Definition of Done

Use this as the final scoreboard. Bot 2 fills `DOCS/15-validation-log.md` by copying this structure and marking each item.

## Must-pass (Definition of Done)

| ID | Requirement | Phone sim | iPad sim | Proof artifact |
|----|-------------|-----------|----------|----------------|
| M1 | App cold launches without crash | | | launch log + screenshot |
| M2 | Guest reaches title/menu with visible frame | | | non-black screenshot |
| M3 | Start exhibition/friendly match with **touch only** | | | screenshots sequence |
| M4 | Survive 60s in-match without crash | | | timestamped log |
| M5 | All GC controls functional (list below) | | | step-10 checklist |
| M6 | Multi-touch: stick + face button together | | | note + screenshot |
| M7 | Layout editor moves a control | | | before/after |
| M8 | Layout persists across process death | | | relaunch screenshot |
| M9 | ⋯ menu opens/closes; pauses or mutes safely | | | screenshot |
| M10 | Resolution 1x and 2x both work | | | scale screenshots + logs |
| M11 | Save export/import round-trip | | | step-13 doc |
| M12 | Only one simulator booted during each test session | | | `simctl list` snippet |
| M13 | No ISO/dol/generated committed | n/a | n/a | `git status` / `git ls-files` check |
| M14 | No JIT/RWX required for iOS build | n/a | n/a | build flags note |

### Control checklist (M5 detail)
A, B, X, Y, Start, Z, D-pad U/D/L/R, Main stick, C-stick, L analog (or digital threshold), R analog (or digital threshold).

## Best-effort (should pass; waivable with DOCS/09 entry)
| ID | Requirement |
|----|-------------|
| B1 | Resolution 3x |
| B2 | Resolution 4x |
| B3 | Audio audible on simulator |
| B4 | Hardware GCController merge |
| B5 | 3+ user layout slots |
| B6 | Portrait layout usable |

## Proof hygiene
- Store under `build/proofs/` (gitignored by default).
- Name `step-NN-description.ext`.
- In validation log, link path + one-line claim.
- Do not paste multi-megabyte logs into DOCS; summarize and point to files.

## Final validation log template (`DOCS/15-validation-log.md`)

```markdown
# 15 — Validation log
Date:
Agent:
Path choice (C/S):
Xcode:
Commits:

## Must-pass
| ID | Phone | Pad | Evidence | Notes |
|----|-------|-----|----------|-------|
| M1 | PASS/FAIL | | | |

## Best-effort
...

## Known issues
- ...

## Git cleanliness
```
git ls-files | rg -i "iso|generated|main.dol|\.gci" || echo clean
```
```

## Sign-off
Bot 2 may stop only when all must-pass rows are PASS (or user-approved waiver recorded in DOCS/09 with ID).
