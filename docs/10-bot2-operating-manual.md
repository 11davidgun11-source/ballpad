# 10 — Bot 2 operating manual

This is the day-to-day runbook. Read once fully, then keep open while executing [07-build-plan.md](07-build-plan.md).

## Mission
Ship a **playable Super Mario Strikers (G4QE01)** experience on **iPhone simulator and iPad simulator** with world-class touch controls and the ⋯ menu. Work only from this repo. Phase 1 research is already in `ref/` and `DOCS/`.

## Non-negotiables
1. **One simulator booted at a time** — always `xcrun simctl shutdown all` before boot ([03](03-simulator-harness.md)).
2. **AOT only on iOS** — no JIT, no RWX, no unsigned downloaded modules ([02](02-native-path.md)).
3. **Never commit** ISO, `main.dol`, `generated/`, saves, screenshots of copyrighted full-motion assets into git if policy says so — default: keep proofs local under gitignored `build/`.
4. **Do not re-litigate architecture** unless both Path C and Path S fail Step 3.
5. **Touch controls are the product** — implement [05](05-touch-control-spec.md), not a minimal d-pad hack, before claiming done.
6. **Self-verify every gate** with a proof file. No honor system.

## Session start checklist
```bash
cd "$(git rev-parse --show-toplevel)"
source build/env.sh 2>/dev/null || true
export REPO_ROOT="$(git rev-parse --show-toplevel)"
export STRIKERS_ISO="${STRIKERS_ISO:-$REPO_ROOT/.local-assets/Super Mario Strikers.iso}"
test -f "$STRIKERS_ISO" || { echo "ISO missing"; exit 1; }
# show progress board
ls build/proofs 2>/dev/null | sort
rg -n "STATUS|PATH=" build/proofs/PROGRESS.md 2>/dev/null || true
```

## Progress board
Maintain `build/proofs/PROGRESS.md`:

```markdown
# Bot 2 progress
- Current step: 3
- Path choice: S
- Last gate: step-02 PASS
- Blockers:
- Next action:
```

Update it every time a gate passes or fails.

## Decision tree (when stuck)

```
Build failure?
  ├─ missing tool → install (Step 1)
  ├─ missing generated → rerun Step 2
  ├─ Path S link error → try Path C (or reverse)
  └─ iOS only failure → confirm macOS still works; bisect host layer

Black screen?
  ├─ no runtime banner → link/init failure (Step 7)
  ├─ banner but black → DVD/ISO path or renderer present
  └─ macOS OK, iOS black → surface/Metal/view lifecycle

Input dead?
  ├─ ballpad_pad_set not called → touch layer
  ├─ called but no game response → HLE/PAD merge order
  └─ hardware controller stealing → prefer-touch mode

Sim weirdness?
  └─ shutdown all → boot one → reinstall app
```

## Failure protocol
1. Capture log tail (last 200 lines) to `build/proofs/fail-step-NN.log`.
2. Reproduce once.
3. If same failure: apply step Rollback.
4. Append entry to `DOCS/09-open-questions.md` with date, symptom, hypothesis, next fallback.
5. Continue via Fallback — do not spin forever on the same command.

## Commit policy
- Commit **only** first-party code under `app/`, `host/`, `scripts/`, and doc updates.
- Never add `ref/**` binary growth unless explicitly asked; `ref/` is research.
- Prefer small commits: `step-06: ios shell launches`.
- Before every commit: `git status` and ensure no ISO/dol/generated.

## Quality bar for "works"
A step "works" only if:
- Gate predicates are true, **and**
- Proof artifact exists and is referenced in PROGRESS.md, **and**
- You could hand the proof to a stranger and they would agree the gate passed.

## Reading order for a fresh Bot 2 brain
1. This file
2. [11-target-repo-layout.md](11-target-repo-layout.md)
3. [07-build-plan.md](07-build-plan.md) Step 0
4. [02](02-native-path.md) + [03](03-simulator-harness.md)
5. Specs 05 and 06 when you reach those steps
6. [12-acceptance-proofs.md](12-acceptance-proofs.md) near the end

## Definition of Done (exit)
All must-pass items in [12](12-acceptance-proofs.md) green on **both** phone and pad simulators, results in `DOCS/15-validation-log.md`.
