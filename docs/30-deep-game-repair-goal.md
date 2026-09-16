# Ballpad Deep Game Repair — Goal Prompt

`APPROVE DEEP GAME REPAIR`

You are the Ballpad repair agent working in:

`<checkout>`

## Mission

The decomp-driven scene loop now boots and reaches a match, but the product is
not acceptable. Fresh gameplay visibly renders poorly, assets appear malformed
or arrive late, audio is unreliable, performance is poor, and the display path
does not provide trustworthy widescreen behavior. Treat these as symptoms of
real integration defects, not as cosmetic limitations.

Deeply audit the whole fresh live-game path using the pinned complete decomp as
the source of truth. Find the responsible boundary for each symptom, fix the
underlying issue, and leave the app measurably better on both iPhone and iPad
Simulator.

Do not stop after producing a diagnosis. After each evidence-backed finding,
implement the fix, rebuild, and verify it in a fresh run. Continue until every
remaining blocker is either fixed or isolated to a precise external dependency
with reproducible evidence.

## Non-negotiable source contract

```text
DECOMP_URL=https://github.com/yannicksuter/smstrikers-decomp
DECOMP_COMMIT=c0bf2ed65f6220e69a8db1f8f115c867737f315f
MAIN_DOL_SHA1=376d699c99b6b0949abe1b4ceccefdef7828d2b5
SDK_SYMBOLS_SHA256=a2b5da87203a8ea118cab30f7fdc8070280041e80de6cdf6fbf4fca7ac1789bb
DECOMP_WORKTREE=work/decomp/smstrikers-decomp-c0bf2ed
```

Use the pinned decomp checkout and generated maps. Do not silently substitute
upstream, patch the DOL, or infer behavior from timing when the source can
answer the question.

## First action: capture the failure honestly

Before changing implementation, run fresh live gameplay on one phone and one
iPad with:

- renderer diagnostics and frame/present counters;
- asset, texture, TLUT, shader/pipeline, and GX-state diagnostics;
- audio queue/voice/sample-rate/underrun diagnostics;
- guest block rate and fixed-update rate;
- scene/decomp PC lookup and source-function identity;
- screenshots at health screen, title/menu, team selection, stadium/loading,
  first field frame, and 30 seconds in-match; and
- a timestamped log with no unbounded per-frame spam.

Do not use QuickBoot for diagnosis. Do not treat a screenshot of a menu as a
rendering pass. Capture the first visibly wrong frame and the first measurable
regression for every subsystem.

## Required investigation tracks

### Rendering and asset correctness

Trace the first malformed, missing, stale, or late asset from guest request to
visible draw. Use the decomp to verify texture formats, palette/TLUT handling,
texture upload lifetime, copy/resolve ordering, GX state invalidation, vertex
decode, material setup, and frame ownership. Distinguish:

- bad guest data;
- incorrect decomp symbol/object lookup;
- incomplete HLE behavior;
- Aurora/GX translation loss;
- asynchronous upload or cache lifetime bugs; and
- screenshot/layout/compositing defects.

Fix the earliest incorrect boundary. Preserve a fresh-Aurora path and prove
that assets remain correct after the game leaves menus and during motion.

### Audio

Trace disc/file reads through the guest audio path, DSP/AI emulation, sample
conversion, queue submission, buffer lifetime, mixer timing, and iOS output.
Measure underruns, queue depth, callback cadence, format/rate mismatches, and
shutdown/restart behavior. Verify both menu audio and in-match audio on phone
and iPad. Do not call audio “working” because a queue exists; prove audible or
deterministically produced output and absence of recurring underruns.

### Performance and synchronization

Measure guest blocks/sec, fixed updates/sec, render-worker queue depth, present
latency, asset upload cost, audio callback cost, and stalls separately. Identify
whether the bottleneck is guest execution, GX translation, texture/vertex work,
pipeline compilation, synchronization, logging, or SwiftUI/Simulator overhead.
Use the decomp and source call sites to remove avoidable work or correct bad
cache/state behavior. Do not merely raise watchdogs, drop frames silently, or
disable correctness paths.

### Display and widescreen

Audit the complete coordinate chain: guest VI/EFB dimensions, GX viewport and
projection, renderer target, readback, SDL/UIKit window, SwiftUI overlay, and
device aspect ratio. Verify 4:3 correctness first, then implement a clearly
defined widescreen mode that preserves gameplay geometry and does not crop or
stretch unpredictably. Test at least phone and iPad landscape, with screenshots
and measured viewport/active-content rectangles.

### Lifecycle and input

Run cold launch, background/foreground, rotation/aspect changes if supported,
touch/controller handoff, pause/settings, and return to gameplay. Verify that
input sources merge without races and that lifecycle transitions do not strand
guest, renderer, audio, or asset workers. Keep manual input separate from
developer autostart.

## Decomp-first method

For each bug:

```text
REPRODUCE -> CAPTURE FIRST BAD STATE -> READ PINNED SOURCE
-> IDENTIFY SYMBOL/OBJECT/STRUCT LAYOUT -> WRITE A FOCUSED TEST
-> IMPLEMENT MINIMAL FIX -> RUN FOCUSED TEST TWICE
-> RUN ADJACENT REGRESSION -> CAPTURE BEFORE/AFTER EVIDENCE
```

Every decomp-derived claim must name the source file/function, generated
symbol/object constant, relevant address/layout, and runtime evidence. Extend
the source-aware lookup/diagnostic layer when necessary; do not parse logs to
drive runtime behavior.

## Acceptance gates

1. Fresh phone and iPad boots reach the same named scenes and a moving match.
2. The first field frame and 30-second frame are visually coherent, correctly
   composited, and materially free of the currently observed malformed assets.
3. Menu and in-match audio produce the expected stream with no recurring queue
   underrun or format mismatch.
4. Guest, render, and audio rates are measured; the dominant bottleneck is
   identified and the implemented fix improves it without hiding work.
5. 4:3 and widescreen display modes have explicit geometry evidence on both
   form factors.
6. Touch, controller handoff, lifecycle, pause/settings, and fresh restart
   remain functional.
7. Existing decomp contract, generator, lookup, raw-address, scene, native,
   and UI regressions remain green.
8. No protected user changes are discarded; no QuickBoot, DOL experiment,
   renderer rewrite, or threshold relaxation is used as a substitute for a
   fix.

If a subsystem cannot be fixed after three evidence-driven attempts, stop that
track with a precise blocker, retain the strongest reproduction, and continue
auditing independent tracks. Do not declare the whole app healthy because one
track passes.

## Required final report

```text
Overall status: PASS | BLOCKED
Pinned decomp/DOL contract:
Fresh phone evidence:
Fresh iPad evidence:
Rendering/asset root causes and fixes:
Audio root causes and fixes:
Performance measurements and fixes:
Display/widescreen measurements and fixes:
Lifecycle/input evidence:
Tests and regressions:
Before/after artifact links:
Protected files preserved:
Files changed:
Remaining blockers:
Exact next action:
```

Do not commit, push, publish, or open a PR. Leave the final runnable build and
isolated diff ready for owner review.
