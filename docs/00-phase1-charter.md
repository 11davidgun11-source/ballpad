# 00 — Phase 1 charter

## Mission
Research and plan a **native Super Mario Strikers (G4QE01)** port for **iPadOS and iOS**, built on macOS, without building or shipping game assets. Phase 1 ends when `ref/` + `DOCS/01–07` + `DOCS/BOT2_PROMPT.md` are complete enough that a fresh build agent can execute without open research.

## Non-goals (Phase 1)
- Compiling the game, running simulators for gameplay, packaging App Store binaries.
- Committing ISOs, DOL dumps, textures, generated recomp C, or original assembly.

## Ground rules for Bot 2 (preview)
- Exactly one simulator booted at a time (iPhone **or** iPad).
- AOT-only guest code (no RWX JIT on device).
- Touch controls are a first-class product, not an afterthought.
- User supplies legal game copy locally.

## Reading order
See [INDEX.md](INDEX.md).
