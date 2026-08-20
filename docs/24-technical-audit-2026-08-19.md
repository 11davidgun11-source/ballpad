# 24 — Technical audit and next-phase plan (2026-08-19)

> **Execution update:** the complete function-level decompilation changes the
> next work order. Use
> [doc 28](28-decomp-integration-plan-2026-08-19.md) for current implementation
> authority and
> [the Bot 6 loop](BOT6_DECOMP_INTEGRATION_LOOP.md) for agent execution. Docs 27
> and 26 remain the graphics/QuickBoot evidence and verification reference.
> This audit remains authority for broader reproducibility and release context.

## Verdict

**There has been real engineering progress, but not yet release progress.**
Ballpad is a working iPhone/iPad Simulator development build with a native app
shell, game import, touch input, a threaded host, a live Aurora GX rendering
path, and useful diagnostic hooks. It is not ready to be called a stable,
reproducible, or device-validated product.

The slow feeling has a concrete cause: the team has spent most of its effort
making the development path work while the three release-defining questions
remain unresolved or unmeasured:

1. Does the default renderer match the game during a moving match, rather than
   merely display a plausible screenshot?
2. Does the app work on real iPhone and iPad hardware through lifecycle,
   audio, controller, thermal, and sustained-input cases?
3. Can another developer reproduce the native build without inheriting this
   machine's ignored `ref/` and `work/` trees?

QuickBoot is deliberately **not** a product feature today. It is disabled by
default because its Aurora GX restore has malformed players and missing HUD in
moving-match captures. It must stay disabled until the renderer-parity gate
passes.

## Audit scope and observed baseline

This audit reviewed the first-party application, host bridge, scripts, tracked
documentation, recent Git history, and the locally available build artifacts
on 2026-08-19. It did not invent a physical-device result or treat historical
screenshots as a current release certification.

| Check | Result | What it establishes |
|---|---|---|
| First-party Git tree | Clean at audit start; latest product commit is `05bd060` (2026-08-18) | Recent work is committed rather than only residing in a chat/worktree |
| Patch drift | `scripts/check_ref_patches.sh` passed | The documented GXRuntime and StrikersRecomp patches match the live local edits |
| Simulator app build | iPhone Simulator Debug `xcodebuild` passed | The checked-out Swift app links against the current local native archives |
| Input unit check | `work/validation/ballpad_pad_test` passed | Touch/controller merging and its mutex boundary have a runnable native regression check |
| Aurora frontend check | `work/gxruntime-tests/graphics/frontend/aurora_recomp_frontend_tests` exited successfully | The locally built Aurora frontend test binary remains runnable |
| Device validation | No physical device was attached in the latest evidence | Nothing here proves real-device performance, audio, lifecycle, or controller behavior |

The current Simulator evidence in [15-validation-log.md](15-validation-log.md)
and [23-goal-loop-2026-08-18.md](23-goal-loop-2026-08-18.md) is meaningful,
but it remains Simulator evidence. The extensive source and test additions on
2026-08-18 are evidence of implementation progress; they are not a substitute
for the outstanding release gates.

## What is working versus what is not yet accepted

| Area | Assessment | Decision |
|---|---|---|
| App shell, import, controls, menu, saves | Implemented and Simulator-exercised | Maintain with focused regressions; do not redesign during the next phase |
| Default fresh Aurora render | Fresh menus and match captures are coherent in recent Simulator evidence | Accept only as a candidate until static **and moving** Dolphin comparisons are recorded |
| QuickBoot restore | Fast, but visual state is not restored correctly in a moving match | Keep diagnostic-only and exclude from release claims |
| Touch and lifecycle | Strong Simulator coverage, including real overlay driving and pause/resume probes | Repeat on physical phone and iPad before calling the interaction model accepted |
| Audio and controllers | Pipeline/mapping exists; hardware behavior is unproved | Validate only on physical hardware; simulator hooks are regression aids |
| Performance | Simulator samples identify work, but no same-scene device profile exists | Stop making FPS claims until physical Instruments captures exist |
| Build reproducibility | Weak | Treat as a release blocker, not cleanup work |
| Documentation | Decomp-first authority is centralized in doc 28 and Bot 6; older plans are supporting evidence | Use doc 28 for work order, this audit for broader release context, and doc 15 for dated evidence |

## Why the workflow has been prone to wheel-spinning

1. **No single scorecard was authoritative.** `docs/INDEX.md` still named the
   2026-08-10 graphics handoff as authoritative, while newer docs contain
   materially different QuickBoot, renderer, and validation conclusions.
   `docs/15` also preserves early “all green” language beside later, more
   qualified evidence. Historical records are useful, but they cannot be the
   current plan.
2. **The critical visual claim has no repeatable oracle gate yet.** A static
   Dolphin sanity check exists, but the required same-scene moving comparison
   is still open. This makes renderer work easy to judge from an encouraging
   screenshot and hard to prove.
3. **The build is machine-state dependent.** The app's Xcode target directly
   links ignored archives in `work/`; its headers come from ignored `ref/`
   worktrees; `build/env.sh` carries local paths and simulator IDs; and archive
   merging uses `head -n 119` over a local list. The patch-drift script is a
   good guard, but it does not provide a bootstrap, pinned upstream revisions,
   or a clean-clone build.
4. **The most important UI test is not a fast, reliable CI gate.**
   `TouchMatchTests` intentionally drives billions of guest blocks and has
   historically required hundreds of seconds. It is appropriate as an
   acceptance run, not as the only signal on every change. The documented
   harness non-exit after a successful runtime assertion needs its own fix.
5. **There is no first-party CI/release pipeline.** There is no tracked CI
   configuration, signed archive procedure, device matrix, notices bundle, or
   deployment checklist. This is why a successful local Simulator build cannot
   be promoted with confidence.

## Next phase — certify the default product path

The next phase is **not** another broad feature pass. Its sole outcome is a
credible answer to: “Is the fresh, default Aurora path visually correct and
stable enough to take to real devices?” QuickBoot, wider UI polish, and new
performance tuning are explicitly out of scope until that answer exists.

### Workstream 1: establish the visual oracle (P0)

Time-box: 3 working days.

- Define two reproducible scenes: one static match frame and one 10–15 second
  moving match segment. Record game state, camera, team, renderer scale,
  device profile, build SHA, and input route.
- Capture equivalent scenes from Dolphin using the same local image. Store
  small, reviewable derived artifacts (frame sequence/contact sheet and a
  metrics text file); keep game data out of Git.
- Review HUD, crop, players/joints, ball, lighting/shadows, textures, and
  frame advancement side by side. State pass/fail and list any mismatch.
- If either scene fails, make only the smallest renderer diagnosis/repair that
  the comparison supports, then rerun both scenes. Do not enable QuickBoot.

**Exit gate:** fresh path passes both comparison scenes on iPhone and iPad
Simulator, with commands and artifacts recorded in the validation ledger.

### Workstream 2: turn acceptance evidence into dependable gates (P0)

Time-box: 2 working days, in parallel only after the visual scenes are fixed.

- Split the current test portfolio into a fast smoke lane (build, native pad
  test, menu/input/lifecycle smoke) and a long acceptance lane (touch-to-match
  and sustained input).
- Fix the Xcode test-harness shutdown/non-exit so a passing guest assertion
  produces a passing `.xcresult` without manual interpretation.
- Add a single `scripts/verify_local.sh` command that runs the available
  first-party checks and reports which checks are skipped because local
  generated/runtime inputs are absent. It must not silently claim device or
  renderer parity.
- Use `docs/15-validation-log.md` only as an evidence ledger: every entry must
  include date, build SHA, device/simulator, command, result, and limitations.

**Exit gate:** a fresh local run produces one machine-readable pass/fail
summary for smoke checks; the long lane has a bounded timeout and an actual
Xcode pass/fail result.

### Workstream 3: physical-device truth pass (P1)

Start only after Workstream 1 passes; time-box 3 working days once devices are
available.

- Build and sign a Debug device archive for one supported iPhone and iPad.
- On each device, run 60 seconds of live touch play, background/foreground,
  audio interruption/resume, controller connect/disconnect, save import/export,
  and 15 minutes of thermal/performance sampling with Instruments.
- Record actual frame/present cadence and CPU/GPU data from the same scene;
  distinguish guest rate from presentation rate.
- Record failures verbatim. A device result is never inferred from an arm64
  Simulator result.

**Exit gate:** a two-device matrix is completed with explicit pass/fail/not-run
cells. A failed row becomes the next narrowly scoped bug, rather than a reason
to reopen unrelated renderer or UI work.

### Workstream 4: make the project reproducible (P1)

Start after the product path is visually accepted; time-box 3 working days.

- Commit a dependency manifest containing upstream URLs, immutable revisions,
  required local patches, tool versions, and output hashes. Do not commit game
  data or generated game code.
- Replace the `head -n 119` archive merge with an explicit, checked list or a
  CMake target that owns the archive construction.
- Add a clean-worktree bootstrap/preflight which explains every prerequisite
  and fails before compilation when one is absent.
- Add CI for checks that do not need proprietary game data: formatting/static
  checks, patch freshness when refs are supplied, and native/unit build checks.
- Add release basics: third-party notices inventory, signing/archive checklist,
  and a security/contact policy.

**Exit gate:** a new developer can set up the project from the manifest and
reach a documented preflight/build result without reverse-engineering ignored
directories on this machine.

## Operating rules for the phase

- One issue, one measurable hypothesis, one named gate. No multi-day debugging
  without a recorded before/after result.
- The root README states user-visible truth only. This audit and doc 23 hold
  the technical plan; doc 15 holds dated evidence; older numbered docs are
  history.
- Every merged change must name its gate and update its evidence entry. A
  screenshot without a matching command, SHA, scene, and limitation is not a
  pass.
- Do not start QuickBoot, layout-slot, widescreen, or optimisation projects
  until the phase exit gates say they are relevant. The default fresh path is
  the product under evaluation.

## Progress dashboard

| Milestone | Status now | Next observable proof |
|---|---|---|
| Default fresh renderer reaches a coherent Simulator match | Candidate | Matched moving Dolphin comparison on both form factors |
| QuickBoot | Rejected for product use | No work until fresh-path visual gate passes |
| Simulator interaction/lifecycle | Candidate with substantial evidence | Fast lane + long lane emit reliable Xcode results |
| Physical-device behavior | Not started; no device available in latest evidence | Completed iPhone/iPad matrix |
| Reproducible build/release engineering | Not started | Manifest + clean-worktree preflight |
| Public/release-quality build | Blocked | All four workstreams complete |

This plan should be reviewed after each exit gate. If a gate has not moved,
report the evidence and the blocker; do not fill the gap with unrelated polish.
