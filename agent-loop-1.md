# COMPOUND GOAL-BASED LOOP — Super Mario Strikers → iPad/iOS Native Port

You are an autonomous research-and-planning agent operating **inside this repository**. You work in a goal-based loop: pick the highest-value open goal, act, validate against a gated check, record what you learned, then repeat. You do not stop until every EXIT CRITERION in Phase 1 is met.

You do NOT build, compile, or run anything in this phase. Your single deliverable is a research corpus plus a complete, gated execution plan — culminating in a second goal-based loop prompt (the "Bot 2 prompt") that a later build agent will follow.

---

## GROUND TRUTH & CONSTRAINTS
- Target: a native **Super Mario Strikers** (GameCube, USA rev G4QE01) port for **iPadOS and iOS**, built and iterated on **macOS**.
- Foundation is a **static recompilation / decompilation** of the GameCube binary (see the `smstrikers-decomp` project and any community recomp). The user supplies their own legal game copy; **never** commit game assets, ISOs, or original assembly.
- Assume **no open, reusable touch-control front-end exists** for this class of port (unlike some N64 recomp ecosystems). Your research MUST explicitly confirm or refute this; if something reusable exists, capture it. Otherwise, plan to build touch controls from scratch.
- The build agent (Bot 2) will iterate using the **iOS Simulator and the iPadOS Simulator on macOS, one at a time — never both running simultaneously**. Every plan you write must respect this constraint.

---

## REPOSITORY LAYOUT (create if missing)
- `ref/` — all downloaded research: cloned repos, docs, specs, saved articles, transcripts. One subfolder per source (`ref/<source-name>/`), each with a `SOURCE.md` (URL, commit hash/date, license, why it matters, key takeaways).
- `DOCS/` — all plans and findings you author (see deliverables). Numbered for reading order (`00-…`, `01-…`).
- `DOCS/BOT2_PROMPT.md` — the final generated goal-based loop for the build agent.
- `ref/INDEX.md` and `DOCS/INDEX.md` — living tables of contents you keep current every loop.

---

## THE LOOP (repeat every iteration)
1. **Select** the highest-value open goal from the goal list below (or a sub-goal you've discovered).
2. **Act**: research and pull the needed material into `ref/`, or write/expand a plan in `DOCS/`.
3. **Validate** against that goal's **gated check** (below). A goal is only "done" when its gate passes.
4. **Record**: update `ref/INDEX.md` / `DOCS/INDEX.md`, note open questions and dead ends in `DOCS/09-open-questions.md`.
5. **Re-plan**: if research invalidated an assumption, revise affected `DOCS/` files before moving on.
6. Stop only when ALL Phase 1 exit criteria pass.

Bias toward over-researching. It is better to capture a source you don't end up needing than to leave the build agent guessing.

---

## PHASE 1 GOALS & GATED CHECKS

### G1 — Map the foundation
Research every project relevant to running Strikers natively: the decompilation (`smstrikers-decomp`, USA `G4QE01`), any community recomp, and the broader GameCube-on-native toolchain (dtk / decomp tooling, sysdolphin/GX-equivalent work, and the proven Super Mario Sunshine + Diddy Kong Racing GameCube-native efforts as prior art).
**Gate:** `ref/` contains each relevant repo (with commit hash + license in `SOURCE.md`), and `DOCS/01-foundation-map.md` states, per project: what it provides, decomp/link % or maturity, license, build system, and whether it is a hard dependency.

### G2 — Establish the macOS → ARM64 native path
Determine exactly how the recompiled game becomes a native Apple-Silicon macOS binary: language/toolchain, renderer backend (and whether it must be re-targeted to **Metal/MoltenVK**), audio, filesystem, memory-card/save handling, threading/timing, and any x86/JIT/RWX assumptions that would break on iOS.
**Gate:** `DOCS/02-native-path.md` lists every subsystem with its current state and the concrete work to make it native ARM64, and explicitly flags any **iOS code-signing / JIT / writable-executable-memory** risks with a proposed AOT-style mitigation.

### G3 — Simulator build/test strategy
Research the Xcode toolchain for driving builds and the **iOS Simulator and iPadOS Simulator** headlessly from the command line (`xcodebuild`, `xcrun simctl`), including boot/install/launch/log-capture/screenshot, and how to guarantee **only one simulator runs at a time**.
**Gate:** `DOCS/03-simulator-harness.md` contains exact command sequences for: select-device → boot (one only) → install → launch → capture logs/screenshot → shutdown, plus a "mutex" rule that shuts down any running simulator before booting another.

### G4 — Touch-control front-end research
Confirm whether any reusable open touch-control overlay/front-end exists for recomp/decomp ports. Capture anything close (N64-recomp community front-ends, emulator touch layers) even if not directly reusable.
**Gate:** `DOCS/04-touch-controls-research.md` gives a verdict (reuse vs build-from-scratch) with evidence and links, and a component inventory for a from-scratch overlay.

### G5 — Author the touch-control & UX spec (product requirements)
Specify a **world-class, GameCube-styled** on-screen control scheme, since input is the whole product on a touch device. Hard requirements to encode:
- Full GameCube layout: A/B/X/Y, analog stick, C-stick, D-pad, L/R **analog** triggers + Z, Start.
- **Skinned to look like a GameCube controller** — faithful button shapes, colors (the green A, red B, etc.), and layout.
- **Fully repositionable** (drag any control) and **resizable** (scale each control or groups up/down), with a dedicated edit/layout mode and persisted per-device layouts.
- Latency, multi-touch, dead-zone, and analog-trigger handling defined as first-class concerns.
**Gate:** `DOCS/05-touch-control-spec.md` fully specifies layout, skin, edit-mode, persistence, and input-mapping to the game's controller interface.

### G6 — Author the in-app menu spec
Specify a **three-dot (⋯) menu in the top-right corner, semi-transparent**, containing at minimum:
- **Native resolution boosting: 1x / 2x / 3x / 4x** (internal render-scale, defined against the emulated/native framebuffer).
- **Save file** management (list/load/backup/export of memory-card saves).
- Control-layout editor toggle, and a slot for additional options ("and other crap" — aspect ratio, audio, graphics toggles, controller pairing).
**Gate:** `DOCS/06-menu-spec.md` specifies the menu's trigger, transparency/behavior, and every panel including the 1x–4x scaler and save-file UX.

### G7 — Synthesize the gated build plan
Turn all findings into a single ordered, dependency-aware plan for the build agent: each step has a **precondition gate** ("download X", "confirm Y builds", "renderer must present a frame") that must pass before the next step.
**Gate:** `DOCS/07-build-plan.md` is a numbered sequence from empty-repo → native macOS build → simulator boot → touch-input playable → menu/resolution/saves → validation, where every step names its gate and its rollback.

### G8 — Emit the Bot 2 goal-based loop prompt
Write `DOCS/BOT2_PROMPT.md`: a complete, standalone goal-based loop prompt for the build agent, embedding the specs above by reference.
**Gate:** `DOCS/BOT2_PROMPT.md` satisfies the "BOT 2 PROMPT MUST CONTAIN" checklist below.

---

## BOT 2 PROMPT MUST CONTAIN
The prompt you generate for the build agent must, itself, be a goal-based loop and must include:
1. **Identity & repo context** — build agent working in this repo, sources in `ref/`, specs in `DOCS/`.
2. **A build/test loop** structured as: pick next gated step from `DOCS/07-build-plan.md` → satisfy preconditions (download/install/configure) → build → **run on exactly one simulator at a time (iOS *or* iPadOS, never both)** → capture logs/screenshots → validate against the step's gate → commit or roll back → repeat.
3. **The single-simulator mutex rule** stated explicitly, with the `simctl` shutdown-before-boot sequence from G3.
4. **Gated checks everywhere** — each step blocks the next until its acceptance criterion passes; the agent must self-verify (build succeeds, app launches, frame presents, input registers) before advancing.
5. **The touch-control mandate** — implement the `DOCS/05` spec: GameCube-skinned, repositionable, resizable controls, treated as the core deliverable ("world-class touch controls, used heavily"), built from scratch (no reference implementation assumed).
6. **The menu mandate** — implement the `DOCS/06` spec: top-right semi-transparent ⋯ menu with 1x–4x resolution scaling, save-file management, layout editor, and options.
7. **Definition of done** — a fully playable match on both an iPhone and an iPad simulator, with configurable touch controls and the working menu, plus a validation checklist and known-issues log.
8. **Discipline rules** — never commit game assets/ISOs; keep `DOCS/` and `ref/INDEX.md` updated each loop; log every dead end.

---

## PHASE 1 EXIT CRITERIA (all must be true)
- `ref/` holds every source needed to build with no further open research, each with license + commit recorded.
- `DOCS/01`–`DOCS/07` are complete, internally consistent, and reflect the latest findings.
- `DOCS/BOT2_PROMPT.md` passes the "BOT 2 PROMPT MUST CONTAIN" checklist and could be handed to a fresh agent with zero extra context.
- `DOCS/09-open-questions.md` lists every unresolved risk with a recommended fallback.
- `ref/INDEX.md` and `DOCS/INDEX.md` are current.