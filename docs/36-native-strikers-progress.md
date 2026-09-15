# Native Strikers execution ledger

## Current state

N4's Files-import half is closed, on both form factors, and with it doc 34's F01 and F02. Ballpad's
own store and importer, `mobile/interface/BallpadGameData.mm`, implements the port's two host hooks
over `<container>/Documents/BallpadGameData/` (a `current` file naming the active staged copy under
`import-<uuid>/<name>`), and the app pulls both symbols into its link explicitly -- which is the trap
hypothesis 15 identified. Three of the four vendored delegate actions (re-import/change, folder
import, removal) route there; only controller mapping is still log-only, which is R1 row 7. Doc 34's
F01 and F02 now PASS on the phone (`f01f02-phone-r4`) and on the iPad (`f01f02-pad-r1`), each run
10/10 rows PASS with `problems: []` on the current build (`app 90f7a37767fc`), driven only by real
touches through `scripts/native/run-uitests.sh`. What those rows decide: a fresh install with no data
presents Ballpad's own importer rather than the port's refusal; a valid image chosen in the *Files*
picker stages and activates with the staged bytes byte-identical to the fixture the picker offered
(`S.f01f02.store-bytes`, `da80883ba456`); and a truncated or wrong-game image is refused while the
previously installed data keeps working. Closing F02 needed one harness fix, hypothesis 21: the picker
publishes its container under an identifier no exact match could ever equal, so the walk was looking
for the wrong string rather than failing to scroll.

N0, N1, N2 and N3 are complete. Both pinned mobile dependencies (SDL3, FFmpeg) are built for the
Simulator, the pinned Dawn source is extracted, the attribution/notices package exists and its
integrity gate passes, both Simulator bundles link and are asserted in place (`build.sh --platform
simulator` exits 0 and reports `platform metadata ok ... BallpadStrikers -> iossimulator`), and
the N2 smoke gate passes all five of its rows (the probe presented 90/90 frames on Metal once the
shared host fell back to load 28). The device platform is built as well: SDL3 and FFmpeg are staged
for `iphoneos`, and `build/native/device-release/port/BallpadStrikers.app` is an unsigned arm64 iOS
Mach-O (platform IOS, minos 17.0, sdk 26.5) with no `@rpath`, no loaded library outside the SDK and
system, and no Homebrew or `/usr/local` link. Nothing has run on hardware, and no device runtime
behaviour is claimed.

N4 is in progress. N4-A and N4-B are done: SunPad's nine interface files are vendored byte-for-byte
into `mobile/interface/sunpad/` (still hashing exactly to the table in that directory's README) and
compile into the app, and the port now has a host-UI seam (`include/port/hostui.h`, weak no-ops in
`src/platform/hostui.c`, calls in `src/Game/main.cpp`, merge in `src/platform/input.cpp`) that
`mobile/interface/BallpadHostUI.mm` implements. SunPad's GameCube control set and its three-dot menu
are therefore running over a real game frame on the iPhone 17e Simulator, and a real tap on the
overlay's A button advanced the game's own memory-card screen -- so touch input is being consumed by
the engine, not merely drawn. N4-C (placement, lifecycle, menu routing) and the interface half of
N4-D (the doc 33 gate on phone *and* iPad) have since closed on both form factors, and N4-D's match
half now passes on both as well; the N4 gate itself is still not claimed, and the paragraphs below
say what remains. The one structural surprise is hypothesis 15: a host interface shipped as a static
archive is never pulled in while the port's own weak no-op satisfies every reference, which fails
silently.

N4-C and N4-D now have their interface half closed on **both** form factors, driven by real
coordinate touches rather than injected pad input. `scripts/native/run-uitests.sh` builds a
repo-local XCUITest bundle that carries no target application of its own and addresses the
CMake-built app by bundle identifier; five test methods map one-to-one onto the five
`S.uitest.*` rows, so every claim is read back out of the app after the touch. Phone
`n4d-phone-uitest-r2` and iPad `n4d-pad-uitest-r3` are both all-rows PASS with a freshly
installed current build (`app 5b22cec45b79`, also confirmed as the *installed* binary's hash --
see hypothesis 18). What the rows decide: the three-dot menu publishes all nine vendored rows in
vendored order, the touch-settings panel exposes the vendored controls and its layout editor, a
render-scale choice survives a terminate and relaunch, a dragged control's position survives the
same and the vendored reset alert restores the default and survives again, and the overlay and
its menu still open after a background/foreground cycle. One finding is recorded rather than
smoothed over: the *same* unmodified `UIMenu` is a one-page list on the iPad and a two-page
scrollable collection view on the iPhone, because the phone panel iOS grants is 322 pt of a 390 pt
screen while the iPad panel is 820 pt -- so on the phone the sixth to ninth rows are not in the
accessibility tree until they are scrolled in (hypothesis 17). The rows, their order and their
handlers are the vendored ones in both cases; only the reading needed a scroll. N4-D's Files-import
half is still open, and no N4 gate claim is made yet.

The one question carried out of the iPad match run -- whether the black first live-play frame was a
fade in, a presented one-frame flash, or a capture-path artifact -- is now closed by measurement,
and it is the capture path. Three runs settle it together. A bounded consecutive-frame burst
(`n4d-dense-r2`) captured 278 of the 281 frames across the whole transition window `3080..3360`
with `EVERY=1`, at 970x448, none of them black at `--black 0` or `--black 8`, and the historically
black frame 3232 among them and lit. A nine-shot burst taken immediately after the engine's own
live-play line (`n4d-kickoff-fade-r1`) shows no ramp out of black at all, which is what refutes the
fade. And a Simulator screen recording running alongside a still of the same instant
(`n4d-video-r1`) contains no black frame anywhere in its 3,857 frames, with a minimum per-frame
average luma of 16 -- the video-standard black level -- so the surface as the compositor presented
it was never fully black. Consequence for the rest of this ledger: the still-capture path is not a
trustworthy pixel oracle for a single frame, and the rewritten hypothesis 16 and hypothesis 19 say
why. No pixel assertion here depends on it, and none is taken during a wipe or a scene transition.

The phone half of the N4-D match gate now passes too (`n3-sim-replay-phone-n4d-phone-match-r2`),
so both form factors have the same scored route on the current build. N4 remains open only on its
Files-import half -- deliberately deferred to N5 as its first work item -- plus the F04 per-control
touch drive and F06's rotated relayout, which are N4 gate rows rather than N4-C surface rows.

Since those runs the port gained the disc seam N5's importer needs, and lost a defect that made a
failed start exit by signal rather than by status. A disc the port cannot use is now recorded
instead of fatal -- `include/port/gamedata.h` publishes whether a disc resolved, the title and
text the box would have carried, and a re-resolve -- because `DVDInit` runs from a static
initialiser (`nlMalloc -> nlInitMemory -> DVDInit`), before a mobile host's framework exists, so
a host that takes the player's disc in itself could never be ordered ahead of it. The entry point,
which on iOS runs inside the host's application delegate, asks the host to import and then resolves
again; a host with no importer (every desktop build) reaches the same box, with the same text, that
it always had (`PortHostUIRunGameDataImport` returns 0 and `port_fatal` reports it). The host's
two obligations are `PortHostUIGameDataPath` (joins the port's own search, called from the static
initialiser, so it must not touch a UI framework) and `PortHostUIRunGameDataImport` (UIKit is up);
both are weak no-ops in `src/platform/hostui.c`. Separately,
`GLInventory::~GLInventory()` called `Delete()` unconditionally while `Create()` is what builds
the per-level containers, so every exit path that ends before the renderer exists -- a bad
`STRIKERS_BACKEND` name, and now the unresolved-disc refusal -- died of SIGSEGV inside
`__cxa_finalize` instead of exiting with the status it chose; the existing `m_bCreated` flag
guards it now.

Desktop matrix on the relinked binary, run in a scratch working directory with
`STRIKERS_NO_MESSAGEBOX=1` (the refusal box otherwise blocks until dismissed, which is why the
first attempt at this matrix sat in `SDL_ShowSimpleMessageBox`): with no data the binary exits
**1** printing the unchanged refusal text; with a valid `STRIKERS_DATA` image and the bounded
capture exit it runs, prints `[port] DVD: disc G4QE01 (USA)` and exits **0**; with
`STRIKERS_BACKEND=zzz` it exits **1**. The counterfactual for the crash was taken rather than
asserted: restoring the pre-change `GLInventory.cpp` from `ffeff97^` and rebuilding gives exit
**139** on that same bad-backend run, and restoring the file rebuilds byte-for-byte the same
`macos-release/strikers` (sha256 `5f9a1a1b93f2848e5ce6624afd92d62981a76a968cc5e62fe2f514803c3239d5`).
The Simulator bundle has been relinked and re-asserted on the current fork
(`build.sh --platform simulator` exit 0, `platform metadata ok ... BallpadStrikers -> iossimulator`,
app binary `7e526c45f9b6`), and the patch series has been re-exported.

N3 is complete. `BallpadStrikers.app` itself -- not the probe -- now plays a real native-engine
match on the iPhone 17e Simulator. The whole front end is driven by real input, live play begins,
and the match scores on its own: the engine's own detection, goal presentation, scorer credit,
automatic replay and return to play all follow from that goal, with nothing injected. Proof
`build/proofs/native-strikers/n3-sim-replay-phone-n3-sim-replay-r1/`: driver verdict PASS over 31
steps, `S.run` and `S.provenance` PASS, 8 frame captures and 9 state dumps, 145 s wall. The
goal was observed at match t=10.9 (0-0 -> 0-1) and a second one arrived in open play (0-2 by
t=55.5), which is why no frame is predicted anywhere in the scenario: goal timing is not
reproducible run to run.

Getting there needed four harness fixes, three of them defects rather than features. (1) `wait-log`
could match a line left in a reused log by an earlier run and resolve instantly, so it now skips
lines already present when the step begins. (2) The original S3 anchor `[match] state=4 ot=0 score
0-0` can never match, because the real line carries `t=` and `ball=` between `[match]` and
`state=`; written that way the wait stalled for its full 420 s. (3) The front end needs a memory
card before it will skip its popup, and a fresh proof directory starts with none, so a
one-press-per-screen route stalls on the popup; the runner now seeds the card the port itself wrote
(`build/native/seeds/user/USA/Card A/01-G4QE-MarioSoccer.gci`, sha256 `f7400a468e98acff...`).
(4) `run-scenario.sh` itself died instantly on its own `--run-id` because `common.sh` already
declares a readonly `RUN_ID`; the flag is now `RUN_TAG`.

N1 is complete on desktop: a driven macOS Release run passes the whole front end -- 51 health ->
35 saving_loading -> 39 englegal -> 53 intro movie -> 2 title -> 3 main menu -> 1 background ->
8 choose_captains (captains and sides) -> 9 stadium select -> 43 loading -- and reaches a real
match whose in-engine telemetry reports `valid=1`, `dur=300.0`, a clock advancing to 75.69 s and a
score that changes 0-0 -> 0-1. That run is `n1-nav-v12`; the frames show Mario vs Luigi with a live
HUD, not a menu. Getting there required discarding the earlier "lost press / input race" theory for
the scene-27 memcard popup: the front end is a fixed chain of screens, each with its own pre-input
lock (health 2 s, title 1 s) and its own slide gate, and it needs one press per screen rather than
one press per route. Popup accepts, control-channel presses and a real save-card write were all
measured directly (n1-nav-v7, v8); with a save present the popup is skipped entirely (n1-nav-v9).
Five defects are tracked in the hypothesis log: hypothesis 4 (the scene-35 SIGSEGV was
`-fshort-wchar` lowering wide-string scan loops onto the C library's 32-bit `wcslen`, returning
half the true length), hypothesis 5 (a host `/opt/homebrew` libzstd leaked into the Simulator link
through two independent traps), hypothesis 6 (Aurora's vendored libpng was built shared and
reached the bundle through an absolute build-tree rpath, which a device could never satisfy),
hypothesis 7 (`build.sh` and the test runner both looked for the app bundle at the build-tree root,
where CMake never puts it, so a successful build was still reported as a failure), and hypothesis
8 (the Simulator lock release in `test.sh` could not succeed, so every run left the lock held for
the next one to wait out). An earlier harness defect, where `scripts/native` appended every run's
output to one log file so an earlier run's evidence was read as the current run's, is fixed. Four
of the five N2 smoke rows passed on the first three attempts; the probe row was blocked on the
shared host rather than on the build (with load averages between 135 and 500 a Simulator boot ran
past its budget, and on the retry the booted device was gone again by install time), and it passed
as soon as the host quieted to load 28. Native-engine Simulator gameplay is now claimed and
evidenced (N3, above); the device platform and N4 onward are still open.

- Workspace: `/Users/chrissotraidis/GitHub/ballpad`
- Upstream: `https://github.com/new-coke/strikers`
- Initial pin: `22649cb12c112454a34217429296c95bb181af8a` (v1.1.1)
- Ballpad branch: `codex/native-strikers-ios`; engine fork branch `codex/ios-port` at `c28a6d7`
  (pin + 9 commits), fork tree `15d79868707266c914904c5a487f62d88a44f2ea`, clean. Patch series
  `patches/native-strikers/` is 9 patches, SHA-256 `bc19ccd92c75...`; earlier fork heads were
  `3f7b48c` (pin + 7), `450e5c00` (pin + 6), `431de3bb` (pin + 5) and `cd8640b` (pin + 4).
- Authority: docs 33, 34, 35 and the runbook in the goal objective
- Active phase: N5, with N4 open on two gate rows. N0-N3 are complete. N4-A, N4-B and N4-C are
  DONE; N4-D's interface half and its match half are DONE on both form factors; and N4-D's
  Files-import half is now DONE as well -- doc 34's F01 and F02 PASS on both phone and iPad
  (`f01f02-phone-r4`, `f01f02-pad-r1`, 10/10 rows each). N4 is therefore open only on F04's
  per-control game-consumption row and F06's rotated relayout, which are gate rows rather than
  interface work.
- Next action: the R1 full-adaptation list's remaining rows -- **5** (prove each touch setting has
  a real effect on this runtime: render scale and aspect must reach Ballpad's renderer, the FPS row
  must drive the port's own `PortSetFrameLimit`, and the six touch settings must be reflected by the
  overlay the port reads), **7** (decide the controller-mapping destination), **9-11** (rewrite the
  folder-import title, the report destination and the FPS row), **12** (remove the emulated-CPU row
  that must not ship), **13-14** (diagnostics directory and settings-key domain) and **15**
  (About/Credits) -- then F04's per-control touch drive, F06's rotated relayout, and the R2 audio
  measurement path. Render scale comes before aspect: aspect has a shipped resolve-once latch
  (`src/platform/aspect.c`), so a runtime aspect change needs a small port-side setter first, which
  changes the patch digest. Scenarios
  now run through one durable entry point -- `scripts/native/run-scenario.sh --scenario <name>
  --run-id <id> --device <UDID> [--budget SECONDS] [--form-factor phone|pad] [--force]` -- which
  resolves the app from `ballpad-bundles.txt`, seeds the memory card the front end needs, takes
  the Simulator task lock, records provenance (pin, fork head and tree, patch series, disc image,
  app binary) and writes its rows through `suite_report.py`. The proven N3 route is
  `tests/native/scenarios/n3-sim-replay.scn`; the press anchors are
  `STRIKERS_AUTOPRESS=A@s51+180,A@s2+240,A@s53+120,A@s3+240,A@s8+300,...,LEFT@s8+780,...`, and
  `require-frame N` still only resolves when stderr arrives (normally the next 600-frame
  heartbeat), so it stays a coarse wait.
- Goal ID/status: `01a09ebe-c6b1-7200-a10b-5a52cdef46b7` — active (created 2026-09-14)

## Phase board

| Phase | Status | Evidence / blocker |
|---|---|---|
| N0 Protected baseline | PASS | Baseline + engine provenance recorded; see checkpoint N0 |
| N1 Native desktop baseline | PASS | Build+tests PASS (`build/native/macos-release/strikers`, 12/12 checks, 265 gtests, proof `unit-macos-20260914T093026Z`); desktop runtime presents ~63 Hz on M2 with Dawn/Metal; real gameplay capture PASS in `n1-nav-v12` (whole front end to a match, clock 0 -> 75.69 s, score 0-0 -> 0-1, `valid=1`). Desktop only: no Simulator or device gameplay is implied |
| N2 Mobile builds and dependencies | PASS | SDL3 + FFmpeg + zstd staged for Simulator and now for device, Dawn extracted once from the pinned ref and built from source for each platform, notices gate passing and scoped with an `add_custom_target`. The bundles are fully static and correctly located: hypotheses 5-8 are fixed, so no host zstd and no shared libpng enter the link, `build.sh` exits 0 on the bundle CMake actually produces, and the Simulator lock releases at run end. Simulator bundles are IOSSIMULATOR Mach-O; the device bundle is now built and asserts platform IOS, minos 17.0, sdk 26.5, arm64, unsigned, no `@rpath` and no Homebrew or `/usr/local` link. The smoke gate PASSES all five rows (`smoke-phone-smoke-phone-retry1`: probe presented 90/90 frames on Metal). Device runtime behaviour is not tested -- no hardware is present |
| N3 Complete native Simulator match | PASS | Real native-engine match on the iPhone 17e Simulator: `BallpadStrikers.app` runs the whole front end to live play, the match scores on its own, and the engine's goal presentation, scorer credit, automatic replay and return to play follow. Proof `build/proofs/native-strikers/n3-sim-replay-phone-n3-sim-replay-r1/` has `S.run` and `S.provenance` both PASS, driver verdict PASS over 31 steps; see checkpoint N3 |
| N4 Ballpad interface integration | IN_PROGRESS | N4-A PASS and N4-B PASS: SunPad's interface vendored byte-for-byte (9 files, hashes unchanged) and compiled into the app; a port-side host-UI seam plus the `BallpadHostUI.mm` adapter place SunPad's GameCube controls and three-dot menu over a real game frame, and a real tap on the overlay's A button advanced the game's memory-card screen. Proofs `n4b-hostui-seam-phone-n4b-hostui-seam-r2` (S.run + S.provenance PASS) and `n3-sim-replay-phone-n3-regress-after-n4b` (no regression in the record/replay path). N4-C's host/lifecycle surface PASSES on both form factors through real touches -- phone `n4d-phone-uitest-r2` and pad `n4d-pad-uitest-r3`, all five `S.uitest.*` rows PASS on a freshly installed `app 5b22cec45b79` (superseded by `app 30f2d3eb13ca`, the bounded-capture build, and now by `app 7e526c45f9b6`, which adds the disc seam and the GL fix) -- and the N4-D match half is PASS on **both** form factors (`n3-sim-replay-pad-n4d-ipad-match-r1`, `n3-sim-replay-phone-n4d-phone-match-r2`, both on the current build). The capture-path question the iPad run raised is closed as a readback artifact rather than a fade or a presented flash (`n4d-kickoff-fade-r1`, `n4d-dense-r2`, `n4d-video-r1`; hypotheses 16 and 19). Doc 33's N4 gate's Files-import half is now CLOSED on both form factors: the port side was solved by `c28a6d7`'s deferred refusal plus `PortHostUIRunGameDataImport`, Ballpad's own store and importer (`BallpadGameData.mm`) answers both hooks, and doc 34's F01 and F02 both PASS on phone (`f01f02-phone-r4`) and iPad (`f01f02-pad-r1`), 10/10 rows each with `problems: []` and real touches only. N4 is open only on F04's per-control game-consumption row and F06's rotated relayout. Three of the four delegate actions now route into Ballpad's own store (re-import/change, folder import and removal, commit `ace661b`); only controller mapping is still log-only, which is R1 row 7 |
| N5 Audio, saves and lifecycle | IN_PROGRESS | F01 and F02 PASS on phone and iPad (`f01f02-phone-r4`, `f01f02-pad-r1`, 10/10 rows each): a fresh install presents Ballpad's own importer, a valid image picked through the Files picker stages byte-identically, and a truncated/wrong-game image is refused while the previous data keeps working. The store is `<container>/Documents/BallpadGameData/`. Audio (F09 / R2) is still unrun -- no run so far contains an audio-device open, a MusyX init or an underrun line |
| N6 Performance/render/endurance | NOT_RUN | |
| N7 Clean reproduction and handoff | NOT_RUN | |
| Physical device validation | NOT_RUN | Outside Simulator completion; hardware evidence required |
| Public distribution clearance | NOT_RUN | Separate rights/release decision |

## Required living sections

### 1. Protected files, baseline SHAs, branches and remote

- Pre-existing owner work preserved untouched: docs 33-36 plus
  `docs/research/strikers-ios-feasibility.md`, digest
  `d1614dc872abf45044a4363cc0346a820c3b8469186612cf327ca09aa53a1ea6`. Recorded here as a
  standing obligation: do not let this package drift.
- Ballpad branch `codex/native-strikers-ios` (HEAD `7667635`, the owner's docs package).
- Engine fork (gitignored) `work/native/strikers`, remote `upstream` ->
  `https://github.com/new-coke/strikers.git`, branch `codex/ios-port` at `c28a6d7` (pin + 9
  commits), tree `15d79868707266c914904c5a487f62d88a44f2ea`, clean. Earlier fork heads recorded in
  the checkpoint log: `ffeff97` (pin + 8), `3f7b48c` (pin + 7), `431de3bb` (pin + 5) and
  `450e5c00` (pin + 6).
- `build/` and `work/` are gitignored; `build/proofs/` is gitignored. Proof bundles and
  game-derived screenshots are never committed.

### 2. Dependency manifest, patch digest, toolchain, clean bootstrap

- Manifest: `docs/native-strikers-dependency-manifest.json`
  (schema `ballpad-native-dependency-manifest/1`, 10 components).
- Pinned zstd: version 1.5.7, sha256
  `eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3`, staged and
  hash-verified by the idempotent `prepare_zstd()` at `build/native/deps/src/zstd` and
  recorded in the manifest under `pins.zstd`. That entry documents that
  `mobile/CMakeLists.txt` pre-creates `zstd::libzstd` from the pinned tree, which is the one
  condition under which Aurora consults neither `find_package()` nor pkg-config for it.
- Static-only mobile link graph: `mobile/CMakeLists.txt:60-81` declares `BUILD_SHARED_LIBS OFF`
  before the port is added, so every library Aurora builds from vendored source -- libpng
  included -- is static. A configure of a brand-new build directory then emits no `.dylib`
  target at all, which is what keeps a host or build-tree path out of both bundles; hypothesis 6
  records the defect and the measured cost of the change.
- Patch series: `patches/native-strikers/` — 9 patches, pinned-ref..fork-HEAD, series
  SHA-256 `bc19ccd92c75f70e66d3bd207202a0232f0adbea05c4368d15097e18aef768d2`.
  `export-patches.sh` proves the series reproduces fork tree
  `15d79868707266c914904c5a487f62d88a44f2ea`, and `--check-only` exits 0 on the same
  comparison (re-run 2026-09-15 for this checkpoint). The series has now been stale six times — it
  was missing the Info.plist commit, then the `wcslen` fix, then the two log-only diagnostics,
  then the quit/scene-label commit, then the host-UI seam (which the first `n4b` bundle recorded
  as `0e902174`, 6 patches), then the bounded-capture commit, the GL guard and the disc seam (the
  last two are this checkpoint's fork commits `ffeff97` and `c28a6d7`) — and each time it was
  regenerated. Treat `pinned-ref..fork-HEAD` as the only source of truth and re-export before any
  claim that depends on it. Superseded digests: `ff01d0f5...`, `e13f4db3...`, `51a1ec62...`,
  `0e902174...`, `561efa8c...`; superseded trees: `85429409...`, `f7dbf197...`, `15061aa2...`,
  `51b07cdf...`.
- Toolchain: macOS 26.6.2 / Apple M2 (8 cores); Xcode 26.6 (17F113); SDKs macOS 26.5,
  iphonesimulator26.5, iphoneos26.5; cmake 3.27.1; ninja 1.13.2; Apple clang 21.0.0;
  git 2.41.0. System `python3` is 3.8.10, so all helper Python stays 3.8-compatible.
- Clean bootstrap: `scripts/native/bootstrap.sh --platform simulator` — run id
  `20260914T111343Z`, exit 0 (all three patches already applied, image identity confirmed,
  SDL3/FFmpeg/Dawn already present, zstd already staged). Each phase log is truncated at the
  start of its run (`log_new`), so a log now describes one run rather than accumulating.

### 3. Local data identity

- `.local-assets/Super Mario Strikers.iso`, 1,459,978,240 bytes, game id `G4QE01` (USA rev 0),
  sha256 `da80883ba45619ce3854536d582e6af23cba461fba6383daa652138e869bfb6a`, DOL sha1
  `376d699c99b6b0949abe1b4ceccefdef7828d2b5`. Verified by `bootstrap.sh` on every run.
- No game bytes are downloaded, bundled, committed or copied into the app; the app loads the
  user's own imported data. `STRIKERS_USER_DIR` / `STRIKERS_CACHE_DIR` are always overridden
  away from the default `~/Library/Application Support/Super Mario Strikers/`.

### 4. Architecture, frame ownership, lifecycle, configuration

- Native source engine + Aurora/Dawn, direct Metal presentation. No guest execution, no
  per-frame CGImage/UIImage transport.
- `mobile/` is the iOS superbuild: it forces `AURORA_SDL3_PROVIDER=system` (pinned tree),
  rejects `auto`/`package` for Dawn, and passes `-DFETCHCONTENT_SOURCE_DIR_DAWN` at the pinned
  source revision. Targets: `BallpadStrikers` (app, `com.ballpad.strikers`) and
  `ballpad_probe` (`BallpadProbe.app`, `com.ballpad.strikers.probe`).
- Aurora supports iOS upstream: `if (IOS)` adds `lib/device_ios.mm` (CoreHaptics) and links
  `CoreHaptics`; `lib/window.cpp` forces `SDL_WINDOW_FULLSCREEN` on iOS.
- SDL3 iOS entry: `main` -> `SDL_main` -> SDL's ObjC `main()` (UIApplicationMain) ->
  `SDL_RunApp` -> `SDLUIKitDelegate postFinishLaunch` -> `SDL_CallMainFunction`. SDL's
  `postFinishLaunch` has `exit(exit_status)` commented out, so returning from `main` does not
  terminate an iOS app; an explicit shutdown path is still required for `BallpadStrikers`.
- `PortAuroraConfigure` lives at `src/platform/launch.cpp:160`; `src/Game/main.cpp:676 main()`
  is a blocking while loop, so the UIKit run loop owns the main thread and the engine loop
  has to move off it or be stepped (open N3 work).
- Configuration is `strikers.ini` -> uppercased `STRIKERS_*` environment via `PortConfigLoad()`.

### 5. Phone/iPad test matrix

Every Simulator run this task has made, by form factor. `app` is the binary hash the run recorded
in its `S.provenance` row; `5b22cec45b79` is the N4-C build, `30f2d3eb13ca` the bounded-capture
build, and `7e526c45f9b6` the current one (which adds the GL guard `ffeff97` and the disc seam
`c28a6d7`; `--platform simulator` was re-run and re-asserted on this checkpoint).

| Run id | Form factor | Suite / route | Verdict | app |
|---|---|---|---|---|
| `smoke-phone-smoke-phone-retry1` | phone | N2 smoke (probe present) | PASS | probe |
| `n1-nav-v12` | desktop macOS | full front end to a live match | PASS | `strikers` |
| `n3-sim-replay-phone-n3-sim-replay-r1` | phone | N3 scored match + replay | PASS | earlier |
| `n3-sim-replay-phone-n3-regress-after-n4b` | phone | N3 route, regression after N4-B | PASS | `34dd7109` |
| `n4b-hostui-seam-phone-n4b-hostui-seam-r2` | phone | overlay seam over a live frame | PASS | `34dd7109` |
| `n4d-phone-uitest-r2` | phone | 5 `S.uitest.*` interface rows | PASS | `5b22cec45b79` |
| `n4d-pad-uitest-r3` | pad | 5 `S.uitest.*` interface rows | PASS | `5b22cec45b79` |
| `n3-sim-replay-pad-n4d-ipad-match-r1` | pad | N4-D match half | PASS | `5b22cec45b79` |
| `n3-sim-replay-phone-n4d-phone-match-r2` | phone | N4-D match half | PASS | `5b22cec45b79` |
| `n4d-kickoff-fade-r1` | phone | 9-shot burst after live-play line | PASS (diagnostic) | `5b22cec45b79` |
| `n4d-dense-r1` | phone | dense burst, first attempt | run PASS, `S.provenance` FAIL | `5b22cec45b79` |
| `n4d-dense-r2` | phone | dense burst, 278 consecutive frames | PASS | `30f2d3eb13ca` |
| `n4d-video-r1` | phone | screen recording + still of one instant | PASS | `30f2d3eb13ca` |

Devices this task owns:

- phone: `iPhone 17e` `8619020B-306A-4CA2-B0B3-16C6A3F22472`
- pad: `iPad (A16)` `B3799189-DA65-49EA-AAEF-8E2FAEE70D7A`

`AgePad G5 iPad` `574671AD-6F61-4558-9528-BF946DDB760A` belongs to another task and must not
be shut down. One Simulator is owned at a time via the task lock in `common.sh`; the global
`scripts/sim_mutex.sh` shutdown is never used.

### 6. Timing / memory / audio by scene and build

Only the N1 desktop baseline exists so far: `build/native/macos-release/strikers`
(12,794,264 B, arm64), presents at ~63 Hz on M2 with Dawn/Metal. The binary was relinked
after the `wcslen` fix, which is why the size moved by 48 B. Step time is never reported as
frame rate.

The first Simulator numbers now exist, from N3 on the iPhone 17e: the driven scenario wall-clock
duration is 145.2 s for front end + live play to frame 9000, and the port's own limiter reports
`63.00 Hz (display, +5% for vsync)` with `present mode Fifo` on a BGRA8Unorm surface. That is a
target rate the limiter aims at, not a measured frame rate, and it is a Simulator number: it says
nothing about device performance, and no fps claim may be built on it. The doc 34 performance rows
(warmed >= 58 fps, p95 <= 20 ms, p99 <= 33.4 ms, replay >= 55 fps, <= 2 % game-clock agreement,
>= 20 min endurance) remain unrun and will need real measurement, not a limiter setting.

Audio has no evidence at all yet, and the N3 bundle shows why: the run's log contains no audio
device open, no MusyX init, no underrun line and no queue diagnostic. The only audio-looking record
is the memory card's own settings field (`sound music=10 sfx=10 voice=10 audiomode=0`), which is
saved game state rather than a claim about playback. So the Simulator run is silent so far, and
that is not a defect hidden by N3 -- F09 is simply unrun.

An operator observation, recorded verbatim as reported and not yet verified either way: `the sounds
seem disconnected from the models speaking them, but I'm unsure`. It is a lip-sync/voice-timing
question, so it cannot be answered from a silent Simulator run or from still frames. Treat it as an
open F09 objective with a specific measurement: capture audio and video together on one timeline,
find the model-animation event (the NIS `[nis]` lines and the character voice cues the port already
logs) and measure the offset between the voice onset and the animation it belongs to, on both the
desktop reference and the Simulator. Do not close it by ear on one machine.

### 7. Attribution and asset audit

- `ATTRIBUTION.md`, `THIRD_PARTY_NOTICES.md`, `docs/native-strikers-release-readiness.md`,
  `notices/README.md`, and 17 verbatim notice files under `notices/` (copied, not retyped).
- `scripts/native/verify-notices.sh` -> `scripts/native/lib/notices_check.py`. The inventory
  form passes: schema, unique ids, per-component notice coverage, orphan detection, document
  presence and the three required credit URLs.
- `scripts/native/lib/notice_resources.py` is the build side of doc 35's resource list: it
  copies the tracked notices into `<bundle>/notices/`, writes `manifest.json` and generates
  `resources.txt` (sha256/size/path), so the bundle's list is produced from what was actually
  copied.
- Negative controls proved the gate fails: tampered shipped notice -> FAIL; missing
  `resources.txt` -> FAIL; game-derived branding (`MC_Icon.png`) -> FAIL.
- Two `notice_gap`s remain open and make `--final` fail by design: FFmpeg static LGPL
  relinking/source availability, and reducing `aurora-vendored-libs` to the actually-linked
  set. Shipped state is still `planned`; it flips to `yes` at N7.
- Game-derived branding to exclude from the bundle: `assets/icon/`, `MC_Icon.tpl`, generated
  `src/platform/mc_icon.h`, `settings.*`, and any shipped icon/icns/ico derived from them.

### 8. Hypothesis log

1. **Aurora can supply a Dawn package for an iOS Simulator build.** Observation: three recent
   Dawn releases publish `darwin-*`, `ios-arm64`, `android-*`, `linux-*` and `windows-*` and
   nothing else, while `AuroraDawnProvider.cmake`'s regex `^(...|ios-arm64|android-aarch64)$`
   matches an arm64 iOS configure — Simulator included — onto the *device* archive. Smallest
   change: force `vendor` and build Dawn from the pinned source. Outcome: no silent wrong-slice
   link; platform metadata is never patched to disguise a bad archive.
2. **A partial Dawn extraction was mistaken for a complete one.** Observation: a reaped
   `tar -xzf` left a tree with a plausible top level but far fewer files (91,044 vs 99,136).
   Smallest change: extract into a staging path and rename only after `tar` succeeds, and run
   the long extraction inside a persistent tty session. Outcome: bootstrap claims "Dawn source
   already present" only for a complete tree.
3. **`STRIKERS_BENCHMARK=1` crashes reproducibly.** Observation: SIGSEGV in
   `nlFont::DrawString -> nlTextBox::DrawString -> TLTextInstance::Render ->
   FERender::RenderTimeLineAsset`, after `[card] finished type=7 result=-1 success=0 next=39`
   (`src/Game/SH/SHSaveLoad.cpp:970`); without the variable the run reaches frame 600 / scene 51
   (`art/fe/health_and_safety.fen`) cleanly. Proof
   `build/proofs/native-strikers/n1-clean-b-77255/strikers.log`. The faulting frame was inside
   scene 35 (`art/fe/saving_loading.fen`); `STRIKERS_BENCHMARK` only widened the window that
   reached it. **Superseded by 4**: the crash was scene-35 text layout, not the benchmark path
   and not an AI-demo-specific timeline asset.
4. **The wide-string scan loops were being lowered onto the C library's 32-bit `wcslen`.**
   Observation: `clang++ -O2 -fshort-wchar -S` on the classic `while (str[n]) n++;` scan over
   `unsigned short*` emits `bl _wcslen` (`/tmp/ballpad-wcslen-candidates.s`). macOS has no
   16-bit `wcslen`, so the call is the 32-bit one and returns roughly half the true length.
   Pointer-walk and xor-compare spellings miscompile the same way; add-boolean, `asm volatile`
   barrier and `volatile` spellings are not idiom-matched. Blast radius: 8 `_wcslen` references
   across 7 translation units out of 764 objects (`tlTextInstance_runtime.cpp`,
   `feButtonComponent.cpp`, `SHCupHub.cpp`, `SHLoading.cpp`, `SHChooseCup.cpp`, `nlFont.cpp`,
   `nlTextBox.cpp`); no intentional `wcslen` use exists anywhere in the port. Failure chain: the
   halved length under-sized `TLTextInstance::Render`'s `__builtin_alloca` buffer and
   `FontCharString`'s `nlMalloc` copy while the full-length row walk still wrote
   `Rows[].FirstChar` past it, so `nlTextBox::DrawString` produced a negative glyph count and
   `nlFont::DrawString`'s `alloca` tripped `___chkstk_darwin` (`EXC_BAD_ACCESS` /
   `KERN_PROTECTION_FAILURE`, x0 `0xFFFFFFFE`). Smallest change: add `-fno-builtin-wcslen` to
   `port_flags` in both branches of `smstrikers-port/CMakeLists.txt`. `-fshort-wchar` cannot be
   dropped — `include/port/prelude.h:25-28` `#error`s without it, because six files cast
   `L"..."` to `const unsigned short*`. Outcome: `nm -u` over 604 port objects drops from 8
   `wcslen` references to 0, and the repro scenario acked `press A 4` at frame 604 and ran scene
   51 -> 35 -> 27 past frame 7800 where it previously faulted inside scene 35. Fork commit
   `5b14858`; proof `build/proofs/native-strikers/boot-20260914T110414Z/`.

5. **A host `/opt/homebrew` zstd leaked into the iOS Simulator link.** Observation: the probe
   link died with the bare flag `ld: library 'zstd' not found`, and Aurora still printed
   `aurora: Using existing zstd` even though the pinned zstd source was staged. Two
   independent traps had to be closed. Trap A: `mobile/CMakeLists.txt` tried to isolate the
   dependency search with `set(ENV{PKG_CONFIG_PATH} "")` and `set(ENV{PKG_CONFIG_LIBDIR} "")`,
   but CMake treats an empty `set(ENV{...})` as *unset*, so pkgconf fell back to the
   Homebrew-only `pc_path` compiled into `/opt/homebrew/bin/pkg-config` and answered with
   `-L/opt/homebrew/opt/zstd/lib -lzstd`. Trap B: even after that isolation was fixed, a
   poisoned build directory kept answering, because `FindPkgConfig`'s
   `_pkg_check_modules_internal` only ever *sets* `<prefix>_FOUND` on success, so the
   `ZSTD_FOUND=INTERNAL=1`, `ZSTD_PREFIX` and `ZSTD_LDFLAGS` cached by the earlier bad run
   survived and `PkgConfig::ZSTD` was rebuilt from them with no new `libzstd` query; the
   decisive evidence was a pkg-config wrapper that logged only three `--version` calls and no
   zstd query at all. Smallest change that closes both: make the pin structural rather than
   environmental. `mobile/CMakeLists.txt` now sets the pinned tree's own `ZSTD_BUILD_*`
   options and `add_subdirectory`s `<zstd>/build/cmake`, proves `libzstd_static` exists, and
   defines `zstd::libzstd` as an ALIAS before Aurora is added: Aurora skips every lookup once
   that target exists, and a target created in this file cannot be inherited from a stale
   cache. `CMAKE_IGNORE_PREFIX_PATH` still blocks a host CONFIG package,
   `FETCHCONTENT_SOURCE_DIR_ZSTD` still points at the same tree so the now-unreachable
   fallback cannot fetch a second copy, and the manifest's `pins.zstd` was corrected to say
   the target is pre-created rather than the env isolation being the mechanism. Outcome: a
   fresh clean configure logs no `Checking for module 'libzstd'`, caches no
   `ZSTD_FOUND`/`ZSTD_PREFIX`/`ZSTD_LDFLAGS`/`pkgcfg_lib_ZSTD_zstd`, emits no `PkgConfig::ZSTD`,
   carries `zstd/lib/libzstd.a` (x3) as the only zstd input in the probe link line, has zero
   `lzstd` in `build.ninja`, and has no `-I`/`-L` `/opt/homebrew` or `/usr/local` path in
   either ninja file; the zstd objects compile with the Simulator SDK and `-DZSTD_DISABLE_ASM`.

6. **Aurora's vendored libpng was built shared and reached the app through an absolute
   build-tree rpath.** Observation: `otool -L BallpadProbe.app/BallpadProbe` carried
   `@rpath/libpng16.16.dylib`, resolved by an `LC_RPATH` of
   `.../build/native/simulator-release/_deps/png-build`. The dylib is `platform IOSSIMULATOR`,
   so the probe ran in the Simulator, but nothing copied it into the bundle: on a device the
   app would look for a path that exists only on this host. The macOS build never exposed this
   because `find_package(PNG)` reached `/opt/homebrew/lib` and the desktop binary's rpath
   pointed there instead. Cause: `extern/aurora/extern/CMakeLists.txt:6-10` selects shared
   unless `BUILD_SHARED_LIBS` is *defined*, and on iOS `CMAKE_IGNORE_PREFIX_PATH` is what makes
   the `find_package(PNG)` fallback fail, so Aurora builds libpng from the pinned source --
   shared. On the first configure of a new build directory the variable is still undefined at
   that point, because Aurora computes the choice before the xxhash block that is what leaves
   `BUILD_SHARED_LIBS` in the cache at all; a second configure of the same directory happened
   to correct it, which is what made the defect look intermittent and host-related. Measured
   cost of the change, from diffing the two Ninja graphs: **0 compile edges changed**, 24
   removed (18 `png_shared` compiles, 3 dylib link/symlink edges, 3 phony) and 12 changed
   link/phony/notices edges -- no Dawn object and no source file recompiles, because libpng
   already built its `png_static` target alongside the shared one. Smallest change: declare
   `set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)` in `mobile/CMakeLists.txt` before the port
   is added, which states in the build graph what upstream's own `tools/configure.sh` passes on
   the command line. Outcome: configuring a brand-new build directory produces only
   `png_static` and zero `.dylib` outputs, verified in `build/native/freshcheck-20260914T0855Z`,
   where the 08:25 build directory produced `png_shared` and `libpng16.16.58.0.dylib`.

7. **Both the build script and the test runner looked for the app bundle where CMake never puts
   it.** Observation: `build.sh --platform simulator` finished its Ninja build (the log ends at
   `[626/627] ballpad: placing third-party notices`) and then died, because its post-build
   assertion reads `${BUILD_DIR}/BallpadStrikers.app` while the bundle is at
   `${BUILD_DIR}/port/BallpadStrikers.app`: the `strikers` target belongs to the port's own
   `add_subdirectory()`, so CMake places its bundle in the port's binary directory. The same
   defect was in the test runner, whose `app_path()` joined the same two names, so the
   `platform` and `linkage` rows for `BallpadStrikers.app` could not resolve and reported
   `IN_PROGRESS` -- an unrun required row, which is a failing acceptance status, on a build that
   was in fact correct. This is why the first smoke run reported four rows while the app's own
   platform row could not pass on a bundle that `vtool` shows is `platform IOSSIMULATOR`,
   minos 17.0. Smallest change: publish the paths where they are known.
   `mobile/CMakeLists.txt` writes `ballpad-bundles.txt` with
   `$<TARGET_BUNDLE_DIR:strikers>` and `$<TARGET_BUNDLE_DIR:ballpad_probe>` -- the same
   expression the notices step already relied on -- and both consumers read that file, with the
   plain location and a bounded search as fallbacks. Outcome: `build.sh` exits 0 and logs
   `platform metadata ok: .../port/BallpadStrikers.app/BallpadStrikers -> iossimulator`; the
   smoke suite's four metadata/linkage rows pass, including the row that had never resolved.

8. **The Simulator lock release could not succeed, so every run left the lock held.** Observation:
   `sim_lock_acquire` takes the lock with `mkdir` and then writes an `owner` file *inside* that
   directory, while `test.sh` released it with `rmdir ... || true`, which cannot remove a
   non-empty directory. The `trap - EXIT` one line above disabled the `rm -rf` trap that would
   have cleaned it up, so the failure was silent and the stale `held` directory survived every
   run: the next `test.sh` for a Simulator waited the full 900 s acquisition budget and then died
   with "timed out waiting for the task Simulator lock". Found in `build/native/sim-lock/` after
   the first smoke run, with the owner pid of a process that no longer existed. Smallest change:
   `rm -rf "${SIM_LOCK_DIR}/held"` before `trap - EXIT`, so the trap remains the fallback if the
   removal fails. Outcome: the lock directory is empty after a suite run and the next run acquires
   immediately. This is what makes N6's two sequential device runs possible at all.

9. **The scene-27 memcard popup was not losing presses; the route was one press per screen, not
   one press per route.** Observation: earlier driven runs appeared to press A at the popup and
   stall, which read as an input race or a gate that never opened. Direct measurement refuted it.
   The engine already logs popup state, so the run was instrumented with two env-gated, log-only,
   `// PORT:`-marked diagnostics: `FEPopupMenu::Update` now logs `mMenuCreated`, `mMenuDisplayed`,
   `mAcceptDelayTime`, option count, the highlight, the current slide's `m_time/m_start/m_duration`,
   `mControlInput`, the input lock depth and a live `JustPressed(ctrl, 0x100)` edge; `PadStatus::Update`
   logs the pad's category, `err`, current buttons and its just-pressed/just-released edges. Outcome
   (`n1-nav-v7`): the popup is entered at frame 811, displayed at 824, its slide finishes at 844, and
   a press at frame 939 with `disp=1 acc=0.000 jpA=1` is accepted -- `mAcceptDelayTime` then runs
   0.300 -> 0.000 over about 18 frames and the popup is gone. The gate is real but only covers the
   ~20-35 frames between entry and the slide finishing, so any later press is accepted. Nothing to fix.

10. **A control-channel `press A` is equivalent to `STRIKERS_AUTOPRESS`.** Observation: the same
   route driven entirely through the control channel (`n1-nav-v8`) accepted the popup on the very
   first press after entry and then wrote a real save card, so the two input paths are not different
   in kind: `n1-nav-v8`'s second press produced `[card] create file=MarioSoccer size=19649`,
   `[card] write file=MarioSoccer len=24576` and a `success=1` callback. The earlier claim that
   presses at frames 1201/1210 "never worked" was a misreading of an older log that had no popup
   instrumentation: the press did accept, and a later press drove the about-to-save slide.

11. **The front end needs one press per screen, and each screen has its own pre-input lock.**
   Observation: with a save present (`n1-nav-v9`) the route is 51 -> 35 -> 39 -> 53 -> 2 and the
   memcard popup is skipped entirely, because `SHSaveLoad` only asks when there is no file to load.
   A single press anchored 40 frames after a screen was entered did nothing on the health and title
   screens, which send `JustPressed` nowhere until their own timers elapse: `HealthWarningSceneV2::Update`
   returns before reading input until `mElapsedTime >= 2.0f` (and auto-advances at 60 s), and
   `TitleScene::Update` returns until `m_fTimeElapsed >= 1.0f`. Smallest change: none to the game;
   anchor each press past the lock. Outcome: `A@s51+180` and `A@s2+240` land.

12. **Scene 8 is a per-side phase machine, and the sides phase resets every pad to "no side".**
   Observation: a single A at scene 8 moved a slide but the scene stayed put, and pressing A again
   once or twice produced `POPUP_NO_SIDES_CHOSEN` (`n1-nav-v11`) rather than a forward transition.
   Cause, from source: under single-player input `IChooseCaptain::GetSide` walks side 0 and then
   side 1, each through `PHASE_CHOOSING_CAPTAIN` -> `PHASE_CHOOSING_SIDEKICK` -> `PHASE_READY`, and
   the A branch only advances the phase once that grid's slide has finished
   (`slide->m_time >= slide->m_start + slide->m_duration`), so it takes four presses. On `UPDATE_GO_FORWARD`
   the scene switches to `ST_CHOOSE_SIDES` and calls `ResetAndPositionControllers(true)`, which sets
   every `mPlayingSides[i]` back to -1 -- so A alone cannot ready a pad; a side has to be chosen
   first, and on a fresh setup both `CheckControllers(0)` and `CheckControllers(1)` deny the first
   move on that pad. One `LEFT` (FE remap index 11 -> `PAD_BUTTON_LEFT`) moves pad 0 to side 0 and
   clears the guard, and the next A returns `UPDATE_GO_FORWARD` and pushes scene 9. In scene 9, A
   is only read when neither direction's auto-press is held, so the confirm press must carry no
  direction. Outcome: `A@s8+300,A@s8+420,A@s8+540,A@s8+660,LEFT@s8+780,A@s8+900,A@s8+1020,A@s9+300`
  reaches the match in `n1-nav-v12`.

13. **`wait-log` could satisfy itself from a previous run's output.** Observation: the N3 scenario
   resolved a wait almost instantly and then sampled a state the current run had not reached, in a
   proof directory that already held an earlier run's log. Cause: the driver greps only as far as
   the needle, and a reused `app.log` keeps every line the earlier run wrote, so a needle that was
   already present resolved without the app doing anything. Smallest correct change: `wait-log`
   records the file's byte offset when the step starts and will only match text appended after that
   point. Outcome: a wait now means "this run did this", not "this text exists somewhere".
14. **The new scenario runner died on its own `--run-id` because the name was already readonly.**
   Observation: `./scripts/native/run-scenario.sh ... --run-id n3-sim-replay-r1` exited immediately
   with `line 25: RUN_ID: readonly variable` and produced no bundle at all. Cause: `common.sh`
   declares `readonly RUN_ID` as its own default run id, and the new runner reused the name for a
   different value. Smallest change: name the runner's flag variable `RUN_TAG` and pass it through
   to the driver and `suite_report.py` as `--run-id`. Outcome: exit 0. Worth remembering because
   `common.sh` is sourced by every entry point, so any new script that assigns a common name dies
   the same way.

15. **A weak no-op in the port silently defeats a host interface shipped as a static archive.**
   Observation: after the adapter was written and the app rebuilt, the app linked, launched and
   presented a frame exactly as before, with no touch controls anywhere -- and `nm -m` showed all
   four hooks still `weak external` in the app binary and zero `SunPad` classes in it, even
   though the adapter's archive had compiled cleanly and was named in `target_link_libraries`.
   Cause: the port defines these four symbols itself, weakly, in its own object file. A weak
   definition in an already-linked object is still a definition, so no undefined reference to
   these symbols survives to the point where archives are searched; the adapter's archive is
   never opened and the member holding the strong definitions is never pulled in. Asking for the
   symbol by name (`-Wl,-u,_PortHostUIPollPad`) does not help, for the same reason -- there was
   never an undefined reference to force. Smallest correct change: pull the adapter in
   unconditionally, with CMake's `$<LINK_LIBRARY:WHOLE_ARCHIVE,ballpad_hostui>` on the app
   target. Outcome: all four hooks are `external` (strong) in the app binary and eight
   `_OBJC_CLASS_$_SunPad*` symbols are present. Recorded because the failure is invisible --
   nothing warns, and "the controls are simply gone" is the only symptom there is.
   **Extended 2026-09-15:** the port now defines six hooks, not four -- `c28a6d7` adds
   `PortHostUIGameDataPath` and `PortHostUIRunGameDataImport` as weak no-ops in the same
   `src/platform/hostui.c`, so no symbol list ties them to the pull that already exists. The trap
   is identical and the consequence is worse than missing controls: an adapter that is not pulled
   in leaves `RunGameDataImport` answering 0, so a host with no side-loaded data still refuses to
   start and the importer *appears* implemented while never being called. Whatever mechanism the
   app uses for the four interface hooks has to name these two as well.

16. **The all-black kickoff frame is a capture-path artifact, not a fade and not a presented
   flash.** Observation history: a 100%-black framebuffer -- byte-for-byte all-zero, `--black 0`
   reporting min 0, max 0 and 100% -- was captured at the first live-play frame in the iPad N4-D
   run (frame 3232, render size 1180x820) and in the earlier phone run (frame 3155, 970x448),
   while every other sample in the same bundles was lit; and two other runs captured the *same*
   frame lit. One sample cannot separate the two explanations, and they point at opposite
   conclusions: the field fades in from black at kickoff and the sample landed on the fade's first
   frame (engine correct, sample early), or the capture path races the frame it names (a real
   visible flash would be an F03/F05 correctness question). A dense burst settles it.
   `tests/native/scenarios/n4d-kickoff-dense.scn` captures *consecutive* frames
   (`STRIKERS_CAPTURE_EVERY=1`) across the whole transition window rather than 9 sparse ones, and
   it needs the inclusive `STRIKERS_CAPTURE_FROM`/`STRIKERS_CAPTURE_TO` window that fork commit
   `3f7b48c` adds, because `EVERY` alone would write a file for every frame from frame 0. Run
   `n4d-dense-r2` (phone, app `30f2d3eb13ca`, `S.run` and `S.provenance` both PASS) is
   decisive: 278 of 281 requested consecutive frames were present, all at 970x448, with means
   92.0054..93.0904 and **zero black frames at both `--black 0` and `--black 8`**, the worst
   dark-pixel fraction being 0.19%. The engine's `[match] ... state=4` line lands between the
   shot at frame 3231 and the shot at frame 3232, so live play begins at exactly the frame that
   captured black before -- and that frame is lit here (92.9252, flanked by 92.9043 and 92.9129).
   The burst's only structure is a shallow smooth dip to 92.0054 at frame 3155, recovering to
   92.07 by 3175: a 0.14 luma drift, i.e. the *other* historically-black frame reads a local
   minimum and no fade. The phenomenon is therefore not tied to the transition, not deterministic
   at a frame, and not iOS-specific: the desktop `n1-nav-v12` bundle holds a black frame at 3606
   whose own dump (frame 3602) reports `state=4 clock=7.82 pres_t=11.87` -- **7.82 s into live
   play**, where no kickoff fade can be, which refutes the fade explanation outright. Cause: the
   readback races the frame it names, the same path whose log-to-file accounting goes scrambled
   under a dense burst (hypothesis 19). Command-buffer ordering is *not* the mechanism: in
   `aurora.cpp` `end_frame()` the resample and the present blit into the swapchain are recorded
   before `capture::record(encoder)`, all in one encoder submitted once, so a same-frame clear
   cannot be observed by the copy. Smallest change: none. A real presented one-frame flash stays
   *possible and unsupported* -- only a swapchain-side or capture-video check could settle it --
   so the honest handling is to record it, keep every quantitative claim off the capture path, and
   stop reading the first live-play frame as either a defect or a pass. This supersedes the
   earlier "legitimately black / it is a fade-in" wording.
17. **The vendored menu is the same `UIMenu` on both form factors; iOS only grants it a shorter
   panel on the phone.** Observation: every phone UI-suite method failed with "Touch Control
   Settings… not found" while the identical build passed on the iPad, and the failure looked like
   a missing row. Cause, from the tree the phone run captured: the menu is a `CollectionView` of
   {{535, 12}, {250, 390}} inside a 322 pt panel carrying "Vertical scroll bar, 2 pages", and a
   collection view publishes only the cells currently on screen, so rows six to nine are not in
   the accessibility tree until scrolled in. On the iPad the same call produces a 236x820 panel
   with all nine rows present in one pass. Nothing in `SunPadGameOverlay.mm` branches on idiom and
   the vendored bytes are unchanged, so this is UIKit's presentation of an unchanged menu, not an
   adaptation. Smallest correct change: the *test* walks the menu -- bounded scrolls, recording
   each row's first sighting and its vertical position -- instead of reading it once, and asserts
   that every vendored row is reachable and first sighted in vendored order. Outcome: phone
   `n4d-phone-uitest-r2` passes all five rows, and "a row is missing" is no longer
   indistinguishable from "a row is below the fold". Recorded because the two conclusions point
   at opposite fixes, and an existence check alone cannot tell them apart.
18. **The UI harness kept none of its own preflight evidence, which made a stale-install question
   unanswerable.** Observation: `uitest-pad-n4c-uitest-r2` passed every row but its bundle held no
   `==> boot` or `==> install` line, so a later reader could not tell whether the suite had driven
   the current build or an app left installed by an earlier run. Cause: `log()` writes to stdout
   only, and `log_new "$LOG"` truncates the phase log immediately before `build-for-testing`, so
   every line decided earlier -- device, form factor, app path and hash, seed, boot, install -- was
   discarded from the bundle. Smallest correct change: a `preflight()` helper appends those lines
   to `preflight.log` in the proof directory as they happen, and after the install the *installed*
   binary is hashed out of the Simulator's own bundle container and recorded next to the
   build-tree hash. Outcome: both current bundles show `installed binary 5b22cec45b79...` equal to
   the build-tree `app binary 5b22cec45b79...`, so install provenance is now evidence rather than
   an inference from the script's control flow. The underlying script behaviour was never wrong:
   `install` runs unconditionally, booted device or not.

19. **A dense capture burst scrambles the capture path's own log-to-file accounting.** Observation:
   in `n4d-dense-r2` the port logged 281 `[shot] frame N -> path` lines and Aurora logged 281
   `Wrote frame capture to path` lines, i.e. every frame of the window says it was written -- but
   only **271** distinct paths appear across all 281 `Wrote` lines, 10 paths are logged twice,
   nine files that exist on disk are never named by any `Wrote` line, two paths that *are* logged
   do not exist, and three `[shot]` lines name files that were never produced (frames 3081, 3288,
   3325). The earlier `n4d-dense-r1` showed the same shape (259 distinct paths, 22 duplicated, 22
   unlogged). Cause: the `[shot]` request and the `Wrote` completion are two events on a path that
   is not serialized against the frame it belongs to, and under the load of a one-capture-per-frame
   burst they drift out of step -- which is the same non-determinism hypothesis 16 measures as an
   intermittent all-zero file. Smallest change: none yet; this is recorded because it is the reason
   one-sample runs disagreed with each other, and because it means `Wrote frame capture` must not
   be read as a count of frames actually captured. A future hardening (capture the `[shot]` index
   into the file itself, or resolve the readback before the next request) is worth doing before any
   claim needs a per-frame capture identity, but nothing in doc 34 does.

20. **A process that ends before the renderer exists ran the GL inventory's destructor anyway.**
   Observation: `STRIKERS_BACKEND=zzz` exited **139** -- SIGSEGV during `__cxa_finalize`, faulting
   in `GLInventory::Delete` -- on the same `macos-release/strikers` that exits 0 with a valid
   disc. Cause: `glInventory` is a static object, so its destructor runs on every exit path, and
   `~GLInventory()` called `Delete()` unconditionally while `Create()` is what builds the 16
   per-level containers, their lists and their AVL trees; `ReleaseLevel()` then dereferenced a
   null `m_pFileData[nLevel]`. The backend name was incidental -- the unresolved-disc refusal the
   entry point reports takes the same path, so "this app cannot start" presented as a crash rather
   than as the explanation the port had already written. Smallest change: guard the destructor with
   the `m_bCreated` flag `Create()` and `Delete()` already keep for exactly this question, so no
   new state is added. Outcome, measured both ways on this machine rather than asserted one way:
   with the pre-change `GLInventory.cpp` restored from `ffeff97^` and rebuilt, the bad-backend run
   exits 139; with the guard it exits 1, and restoring the file rebuilds byte-for-byte the same
   binary (sha256 `5f9a1a1b93f2848e5ce6624afd92d62981a76a968cc5e62fe2f514803c3239d5`). Recorded
   because a startup refusal has to stay readable: a signal tells a reader nothing about what the
   port was trying to say.

### 9. Command mapping

21. **The F02 picker walk was not failing to scroll -- it was looking for a string no element could
   ever have.** Observation: the run's own attached hierarchies show Files publishing the app's
   folder as `identifier: 'Ballpad Strikers, Container'` with `label: 'Ballpad Strikers, 4 items'`,
   so an exact-match `pickerMatch(["Ballpad Strikers"])` could never resolve: both strings that
   exist are the display name *plus a suffix*, and the label additionally carries the item count.
   A second measured detail: tapping `Browse` lands on the locations root (`Title: On My iPhone`),
   not on the folder, so reaching the folder is two hops rather than one. Smallest change: add
   `pickerContainer(named:timeout:)` -- a BEGINSWITH match that excludes `BackButton` -- and use it
   as the third pass's fallback, with both measured `Browse` outcomes recorded in the method comment.
   Outcome: `--only testRefusedImportKeepsThePreviousInstallationUsable` PASSes in 209 s with all
   three picker selections landing, and the full phone (`f01f02-phone-r4`) and iPad
   (`f01f02-pad-r1`) suites then pass 10/10 rows each with `problems: []`. Recorded because the
   earlier attempts were spent on timeout wording and scroll strategy for a mismatch no wait could
   fix: a harness that cannot see an element is not evidence that the element is absent.

The required surface is exactly `bootstrap.sh`, `build.sh --platform macos|simulator|device
--configuration Release`, `test.sh --suite unit|smoke|acceptance --device <UDID>`,
`export-patches.sh`, `verify-notices.sh` and `verify-clean.sh` — all under `scripts/native/`.
No renames were needed.

### 10. Final artifacts and limitations

Not yet produced. Remaining: Simulator app bundle, unsigned device build, the N7
clean-reproduction proof, and the explicit statement that physical-device performance,
battery/thermal quality and legal/public-release readiness are not established here.

## Operator-added requirements

Work the operator added after the runbook was written. These are requirements to schedule, not
deviations from scope.

### R1 — Adopt SunPad's interface in its entirety (added 2026-09-14; target N4/N5)

Instruction, verbatim in substance: after stability, implement SunPad's interface and adapt it in
its entirety for Ballpad, including the three-dot menu and the controls exactly as they are, because
this is a GameCube game.

Reference: the sibling project `/Users/chrissotraidis/GitHub/sunpad`, directory `apple/ios/`. The
intended interface is `SunPadGameOverlay` — a UIKit view above the render surface that owns the
persistent three-dot primary-action menu, render-resolution choices, the touch-control settings
surface, and the GameCube control set (main stick, C-stick, D-pad, A/B/X/Y/Z/Start/L/R). It
publishes touch state through `SunPadInputMixer` behind `SunPadInputState.h`, and exposes delegate
hooks for game-data change, folder reimport, removal, controller mapping, diagnostics and
performance profile (`apple/ios/SunPadGameOverlay.h`). Supporting pieces are
`SunPadGameOverlay.mm` (1,725 lines), `SunPadSettings`, `SunPadInputMixer` and
`SunPadControllerMapping`.

Why "exactly as they are" is reachable here: the new Ballpad iOS app is CMake plus Objective-C/C++
(`mobile/CMakeLists.txt`, `mobile/ios/Info.plist.in`, `mobile/probe/main.c`), the same technology
as SunPad's overlay, so the overlay can be adopted on its own terms rather than re-derived. This is
distinct from the legacy SwiftUI surface under `app/Ballpad/`; doc 21 records what that surface had
already borrowed from SunPad, and it was partial.

Deliverable, in phase order:

- N4: the three-dot menu and the GameCube control geometry adopted as-is, with the normalized
  stick/trigger boundary and the controller-visible/hidden behaviour.
- N5: the menu's data, settings, diagnostics and lifecycle actions routed to Ballpad's own importer,
  settings store and diagnostics rather than to the legacy host.

Open decision at N4, flagged rather than assumed: whether the overlay source is vendored as a
tracked copy with Ballpad-side changes carried in the patch series, or reimplemented in Ballpad's
own Objective-C++ against the same geometry. "Exactly as they are" favours the first, so geometry,
hit-testing and menu behaviour cannot drift; the second is only justified if the overlay's
Sunshine-specific assumptions resist Ballpad's runtime. Either way the controls and the three-dot
menu are a fidelity requirement, not a starting suggestion. Reuse is also a doc 34 concern: the
runbook already says to reuse the existing interface instead of redesigning it.

### R1 — The full-adaptation to-do list (operator restated 2026-09-14; standing requirement)

The operator restated the requirement while N4-C was being closed: implement SunPad's interface and
adapt it **in its entirety** for Ballpad, including the three-dot menu and the controls exactly as
they are, because this is a GameCube game. That is R1 already; what follows is the part R1 did not
yet have -- the vendored surface enumerated, item by item, so "in its entirety" is checkable rather
than asserted. Nothing here is a new scope decision, and the fidelity rule is unchanged: the nine
vendored files stay byte-for-byte and every adaptation lives in `mobile/interface/BallpadHostUI.mm`.

**Restated again 2026-09-15**, in the same message that re-raised the audio observation below:
SunPad's interface implemented and adapted in its entirety for Ballpad, three-dot menu and controls
included exactly as they are, because this is a GameCube game -- and this time explicitly as a
to-do-list item. Nothing in it changes scope; the table below *is* that list, and the operator's
two requirements are worked in the order the list gives them, with item 5 (a setting that actually
reaches the runtime) and item 12 (a row that must disappear) being the two that cannot be satisfied
by wiring alone.

What "exactly as they are" has already decided, and what is still owed:

| # | Vendored surface | State | What is owed |
|---|---|---|---|
| 1 | Nine-file vendored set (`SunPadGameOverlay.{h,mm}`, `SunPadInputState.h`, `SunPadInputMixer.{h,mm}`, `SunPadSettings.{h,mm}`, `SunPadDiagnostics.{h,mm}`) | DONE at N4-A, hashes still match `mobile/interface/sunpad/README.md` | Re-verify the hash table at N7 on the final build |
| 2 | GameCube control set: main stick, C-stick, D-pad, A/B/X/Y/Z, Start, L, R | DONE at N4-B (published through `SunPadInputMixer` -> `PADSetVirtualStatus`) | Prove game consumption per control at a state boundary where each mapping is observable, and stick + action **simultaneously** (F04) |
| 3 | Three-dot button, 9-row menu, vendored order, vendored handlers | DONE at N4-C, both form factors, real touches | None for geometry; N5 rewrites three row titles/destinations (rows 6-8 below) and the untitled rows stay untouched |
| 4 | Menu title | DONE at N4-C (`BallpadGameOverlay -buildMenu` re-wraps the vendored menu's children under the bundle's display name) | None |
| 5 | Touch-control settings surface: render resolution, opacity, control size, hide-when-controller, modern C-stick, move/resize, reset | Surface DONE and exercised by real touches | Prove each setting has a **real effect on this runtime** rather than only persisting: render scale and aspect must reach Ballpad's renderer, the FPS row must drive Ballpad's frame stats, and the six touch settings must be reflected by the overlay the port is reading |
| 6 | `gameOverlayRequestsGameDataChange` / `…FolderImport` / `…Removal` | DONE: all three route to Ballpad's own store (`BallpadGameData.mm`) since commit `ace661b`; the fourth delegate action is row 7 | None outstanding for routing. The pre-`main()` `DVDInit()` ordering is solved on the port side (`c28a6d7`), and F01/F02 exercise all three paths on both form factors (fresh import, re-import/refusal, removal's consequence) |
| 7 | `gameOverlayRequestsControllerMapping` | Still log-only, and the only one of the four delegate actions that is (see the comment in `BallpadHostUI.mm`) | Decide at N5 whether Ballpad adopts SunPad's narrow A/B/X/Y/Z remap (`SunPadControllerMapping` was deliberately not vendored at N4) or answers with Aurora's own mapping surface. There is no remap store to route into until that decision is made, so the log line names the open decision rather than hiding a missing route |
| 8 | `gameOverlayDiagnosticContext` / `gameOverlayPerformanceProfile` | DONE at N4-B (both answer from this build) | Keep truthful as the runtime gains features |
| 9 | Row "Import from SunPad Folder" | Untouched, N5 | Rename against the same handler |
| 10 | Row "Report a Problem…" and its alert copy; GitHub issue destination | Untouched, N5 | Correctness problem, not cosmetics: as-is a Ballpad report lands on SunPad. Ballpad has no issue template and messaging maintainers is outside this assignment, so N5 writes the local diagnostic report and chooses the destination deliberately |
| 11 | Row "Experimental 60 FPS (Restart Required)" | Untouched, N5 | Make it the port's own `PortSetFrameLimit` instead of a Sunshine boot hack |
| 12 | Row "Experimental Performance Mode (Restart Required)" | Untouched, N5 | **Must not ship as-is**: it toggles a 90% emulated CPU clock a native port does not have, which is exactly the nonfunctional placeholder doc 33 forbids |
| 13 | `SunPadDiagnostics` log directory (`<Library>/.../SunPad/runtime.log`, confirmed by source) | Untouched, N5 | Rename to Ballpad's own directory |
| 14 | `SunPadSettings` persistence keys (`SunPadRenderScale`, `SunPadControlSizeScales`, … in `standardUserDefaults`) | Untouched, N4 | They already live in Ballpad's own app domain, so there is no cross-app leak; renaming is a migration question for N5 rather than an N4 defect |
| 15 | Offline About/Credits surface naming upstream contributors and bundled notices (F13) | Not built | N5, with doc 35's text |
| 16 | Physical-controller visibility merge | Bridged at N4-B | F12's merge/connect/disconnect boundary test, and the hardware row left `NOT_RUN` |

Two of these are the reason the list is written down rather than tracked mentally: item 12 is a row
that must disappear rather than be wired, and item 5 is the difference between a surface that
persists a value and one whose value changes anything.

### R2 — The operator's audio observation is unverified (added 2026-09-14; target N5/F09)

Reported: "the sounds seem disconnected from the models speaking them, but I'm unsure". Recorded as
an open question with a defined measurement rather than as a confirmed defect; see section 6. It
cannot be settled by ear, from a silent Simulator run, or from still frames.

**Restated 2026-09-15**, together with R1. Still unverified, and section 6 records why the first
step is getting *any* audio out of a Simulator run before the offset can be measured at all: no run
so far contains an audio-device open, a MusyX init or an underrun line. The measurement stays as
defined -- audio and video on one timeline, the animation event located from the port's own
`[nis]` and voice-cue lines, the onset offset measured on desktop and Simulator.

### R1 — N4 plan of record (recorded 2026-09-14, before implementation)

**Decision on the open question above: vendor, do not re-derive.** SunPad's touch interface is
copied byte-for-byte into `mobile/interface/sunpad/` as tracked Ballpad sources, and every
Ballpad-side change lives in a separate adaptation layer (`mobile/interface/Ballpad*`) instead of
inside the vendored files. The reason is the fidelity requirement itself: normalized anchors,
per-control size overrides, hit-testing and the three-dot menu's action set are the things that
drift first when a layout is retyped, and a byte-identical copy makes any future drift a visible
diff against the sibling project. Reimplementing the same geometry in Ballpad's own Objective-C++
was rejected because it cannot be shown to be "exactly as they are".

Vendored set (the overlay plus its three self-contained companions; nothing else is needed):

| File | Role |
|---|---|
| `SunPadGameOverlay.{h,mm}` | Three-dot menu, resolution choices, touch settings surface, GameCube controls |
| `SunPadInputState.h` | The normalized pad struct and button mask the controls publish |
| `SunPadInputMixer.{h,mm}` | Touch/physical merge boundary the overlay publishes into |
| `SunPadSettings.{h,mm}` | Persisted presentation, opacity, size and layout-override store |
| `SunPadDiagnostics.{h,mm}` | Log + problem-report plumbing the menu's report row calls |

`SunPadControllerMapping` is *not* vendored at N4: the overlay does not reference it (only
SunPad's own view controller does), and Ballpad's controller bridge is Aurora's business. It is
reconsidered at N4-C if the physical-controller merge needs SunPad's narrow A/B/X/Y/Z remap.

SunPad is the operator's own sibling project and is GPL-3.0. The vendored copy keeps its headers
and file names, `mobile/interface/sunpad/README.md` records provenance, source hashes and license,
and R1 material is added to the notice inventory at N5/N7 rather than being relabelled as
Ballpad's own.

**Stages, each with its own evidence:**

- **N4-A — vendor and compile.** DONE. The nine files were copied, built into the `ballpad_interface`
  static library (4 `.mm` under `-fobjc-arc`, plus UIKit/Foundation/GameController/QuartzCore), and
  linked into the Simulator bundle. Evidence: a build that compiles the overlay, and a hash table
  showing the vendored bytes are still identical to the source project's (re-verified at N4-B).
- **N4-B — bridge.** DONE. A port-side host-UI seam (the port calls into the app once, right after
  `aurora_initialize`, to build the overlay, and once per frame at the *top* of
  `PortUpdateSyntheticInput` — before `record_pad`/`replay_pad` and before Aurora reads the
  virtual pad, because `SunPadInputMixer` clears latched edges on read, so a publish placed after
  the port's own pad handling would drop a one-frame tap) plus an app-side
  ObjC++ adapter that creates the overlay, reads `SunPadInputMixer`'s merged snapshot, and writes it
  through Aurora's public
  `PADSetVirtualStatus`. The input path is deliberately the *published* pad API rather than a new
  private hook: the port already treats that virtual status as the synthetic-input channel, and
  Aurora merges it with a real controller instead of replacing it.
- **N4-C — host and lifecycle.** Overlay above the render surface, safe-area relayout on both form
  factors, pause with input release, settings persistence, layout reset, and the menu's delegate
  actions routed to Ballpad's own importer/settings/diagnostics rather than to SunPad's host.
- **N4-D — verification.** The doc 33 N4 gate, driven through real touch input, on phone and iPad.

Order of work inside N4-A is copy, compile, then the hook, because a compiling overlay is the cheap
way to find out whether the vendored set is self-contained on this toolchain.

### R1 — N4-C scope, and the vendored SunPad-isms (recorded 2026-09-14, before implementing N4-C)

N4-C is **host placement and lifecycle**, not the data path. Recorded split, so the two are not
re-litigated at every menu row:

| Stage | Contents |
|---|---|
| N4-C | Overlay above the render surface; safe-area relayout on phone and iPad; background input release and foreground controller re-check; settings persistence and layout reset exercised through the real surface; the fidelity-preserving adaptations below |
| N5 | The four delegate callbacks routed to Ballpad's own importer, settings store and diagnostics; the runtime settings bridge (frame limit, frame-stat overlay, render scale, aspect); the problem-report destination; the diagnostics log directory |

The delegate routing moves to N5 rather than staying in N4-C because of the pre-main data path:
the port reaches `DVDInit()` from a static initializer before `main()`, so the app cannot promise
that an importer it runs has executed before the port resolves its disc image. Routing a menu row
to an importer that cannot be ordered ahead of the port would be a row that appears to work and
cannot. R1 itself schedules the routing at N5, and doc 33's N5 gate is the one that requires all
functional rows; N4's gate keeps its Files-import requirement, which becomes N5's first work item
and the one that closes N4-D.

**Vendored SunPad-isms, with the decision taken for each.** `mobile/interface/sunpad/` stays
byte-for-byte; every adaptation below happens in `mobile/interface/BallpadHostUI.mm`.

| # | Item | Location | Decision |
|---|---|---|---|
| 1 | Menu title hardcoded to the string SunPad | `SunPadGameOverlay.mm`, `buildMenu` | **Adapt at N4-C.** A Ballpad subclass re-wraps the `UIMenu` its superclass returns with a Ballpad title and the same children, so every row, order and handler stays the vendored one and only the header changes. |
| 2 | Row titled "Import from SunPad Folder" | `SunPadGameOverlay.mm`, data menu | **N5**, with the routing it belongs to. Renaming it means rebuilding that `UIAction` against the same handler, not editing the vendored file. |
| 3 | "Report a Problem..." opens SunPad's GitHub issue form | `SunPadGameOverlay.mm`, `reportProblem` | **N5**, and a correctness problem rather than a cosmetic one: filed as-is, a Ballpad problem report lands on SunPad. Ballpad has no issue template and messaging maintainers is outside this assignment, so N5 writes the local diagnostic report and chooses the destination deliberately. Documented, not silently inherited. |
| 4 | Report alert copy names SunPad | `SunPadGameOverlay.mm`, `reportProblem` | **N5**, same decision as 3. |
| 5 | "Experimental 60 FPS (Restart Required)" | `SunPadGameOverlay.mm`, menu | **N5 settings bridge.** The row is Sunshine's GMSE01 boot hack; a native port has no such switch. The port already owns a real frame limit (`PortSetFrameLimit`, `include/port/framerate.h`), so N5 makes the row the port's control instead of an emulator boot flag. |
| 6 | "Experimental Performance Mode (Restart Required)" | `SunPadGameOverlay.mm`, menu | **N5, and it must not ship as-is.** It toggles a 90% *emulated* CPU clock, which a native port does not have; leaving it would be exactly the nonfunctional placeholder setting doc 33 forbids. N5 removes or replaces it. |
| 7 | Runtime log directory named SunPad | `SunPadDiagnostics.mm`, log path | **N5**, with diagnostics routing. No user-visible interface effect at N4. |

Menu order (render menu, aspect menu, FPS row, performance row, 60 FPS row, controller mapping,
touch settings, data menu, report row) is part of the geometry claim and is not reordered.
### N5 — Ballpad's Files importer, design of record (recorded 2026-09-14, before implementation)

Reproduced before designing, because the shape of the fix follows from it. The current Simulator
build, installed and launched with no `STRIKERS_DATA`, exits before UIKit exists:

    [port] DVD: 0 files under data/G4QE01/files
    === Super Mario Strikers: game data not found ===
    ...Looked in, in order: 1. <bundle>.app/files (beside the game)  2. data/G4QE01/files...
    [port] (no display for a message box: Application didn't initialize properly, did you include
           SDL_main.h in the file containing your main() function?)

So doc 34's F01 row fails on the current build, and it fails structurally rather than for want of a
screen: the port resolves its disc from a static initialiser (`nlMalloc -> nlInitMemory ->
DVDInit`, `src/NL/nlMemory.cpp:40`), which runs *before* `UIApplicationMain`, while every UIKit
surface a host could show is created *after* it. The port's search reaches only the environment,
the directory beside the executable (the `.app` bundle, read-only on a device) and the working
directory, so a sandboxed host has no writable location the port will ever consult.

**Invariant (what this must not break):** the port's own search order, its error text and its
behaviour on a desktop build stay exactly what they are today, because the N1/N3 proofs and the
`data` / `STRIKERS_DATA` route the scenario runner uses all depend on them.

**Pass criterion:** with the app installed and launched with no environment at all, the app
presents Ballpad's own import screen instead of exiting; a valid local raw USA image chosen
through the Files document picker is validated, staged and activated; that same launch then plays;
an invalid, truncated or wrong-game image is refused with the port's own explanation, leaves the
previous installation usable, and modifies nothing outside the app container (F01, F02).

**Decision: two host hooks and a deferred refusal, not a pre-main trick.**

| Piece | Where | Why this shape |
|---|---|---|
| The port stops exiting on missing or unusable data: it records the title and message it *would* have shown and returns | `src/platform/dvd.c` | A static initialiser cannot present anything, so the decision has to outlive it |
| The entry point, which on iOS runs inside the host's application delegate (UIKit is up), asks the host to run its importer and then resolves again | `src/Game/main.cpp` | The only point in the run that is both after the framework and before any game code reads the disc |
| `PortHostUIGameDataPath()` — a location the port's search consults, before the directory beside the executable | `include/port/hostui.h` (weak no-op in `src/platform/hostui.c`) | This is what makes an import *persist*: without it, data the host stages is invisible to the next cold start. Called from the static initialiser, so the host's implementation must be free of UIKit |
| `PortHostUIRunGameDataImport(title, message)` — the fatal box, handed to a host that has an importer | same | Keeps the desktop path identical: the weak no-op returns 0 and the port calls `port_fatal` with the same text it always did |

Rejected: an `__attribute__((constructor(101)))` in the app that sets `STRIKERS_DATA` ahead of the
port's initialiser. It would work on this toolchain, but it makes the app's data path depend on
`__init_array` priority ordering, it does not solve the no-data launch (there is nothing to point
at), and it puts a load-bearing fact in a mechanism nothing in the build asserts. A documented
seam that a desktop build also exercises as a no-op is checkable; symbol ordering is not.

**Ballpad's side, staged validation and activation.** `mobile/interface/BallpadGameData.mm` owns
the store at `<container>/Documents/BallpadGameData/`: a `current` file naming the active data,
and the staged copy beside it. Validation reuses the port's own reader (`port_disc_open`,
`port_disc_read`, `port_disc_walk`) rather than a second parser, so "valid" means exactly "the
engine can open this" and the refusal text is the engine's own. Activation is a write of
`current` and nothing else, which is what leaves a previous installation usable when a new image
is refused. Both hooks are pure C (`getenv("HOME")`, `stat`, `fopen`) because the port calls
one of them before the framework exists.


## Checkpoint log

```text
Phase / gate: N0 -> N1 (build + tests)
Date / build identity / patch digest: 2026-09-14; macos-release @ fork cd8640b; series ff01d0f5
Source invariant and observed failure: the port builds and its own tests pass on macOS.
Hypothesis: the pin builds with Aurora enabled for arm64 macOS.
Change: pin + patches applied; macOS Release build; ctest + gtests run.
Command / exit status: build.sh --platform macos -> 0; test.sh --suite unit -> 0
Runtime scene / duration / device-or-Simulator: n/a (unit); desktop runtime observed separately
Evidence bundle: build/proofs/native-strikers/unit-macos-20260914T093026Z/
Result: PASS
What this result does and does not prove: proves build + unit correctness, not gameplay or iOS.
Next concrete action: stand up the Simulator dependency and app builds.
```

```text
Phase / gate: N1 (desktop gameplay evidence)
Date / build identity / patch digest: 2026-09-14; macos-release @ fork cd8640b; series ff01d0f5
Source invariant and observed failure: a real match must be driven without the benchmark path.
Hypothesis: the demo/benchmark entry crashes in timeline text rendering; the normal menu path is
the correct evidence route.
Change: none yet — the evidence run is the next action.
Command / exit status: not run
Runtime scene / duration / device-or-Simulator: pending
Evidence bundle: pending (must land under build/proofs/native-strikers/)
Result: FAIL (not yet demonstrated)
What this result does and does not prove: nothing yet; no gameplay claim is made.
Next concrete action: drive menus -> moving match -> goal/replay -> post-match via driver.py.
```

```text
Phase / gate: N2 (dependencies)
Date / build identity / patch digest: 2026-09-14; bootstrap run 20260914T101310Z; series ff01d0f5
Source invariant and observed failure: an iOS Simulator build must not link host libraries, and
Dawn has no Simulator prebuilt slice.
Hypothesis: building Dawn from the pinned source for the Simulator SDK is the only correct path.
Change: force AURORA_DAWN_PROVIDER=vendor + FETCHCONTENT_SOURCE_DIR_DAWN; build SDL3 and a
THP-only static FFmpeg per platform; stage the Dawn extraction and rename only on success.
Command / exit status: bootstrap.sh --platform simulator -> 0
Runtime scene / duration / device-or-Simulator: n/a
Evidence bundle: build/native/deps/{sdl3,ffmpeg}/simulator, build/native/deps/src/dawn
Result: PASS (dependencies); app build and smoke gate still running
What this result does and does not prove: proves the dependency sets exist for the Simulator SDK
and carry Simulator platform metadata; it does not yet prove the app links or runs.
Next concrete action: finish build.sh --platform simulator, then run the smoke gate.
```

```text
Phase / gate: N2/N7 (attribution inventory)
Date / build identity / patch digest: 2026-09-14; series ff01d0f5
Source invariant and observed failure: a shipped component without a notice, or a manifest that
disagrees with the shipped resources, must fail.
Hypothesis: an integrity checker plus a build-generated resource list makes drift detectable.
Change: added ATTRIBUTION.md, THIRD_PARTY_NOTICES.md, the release-readiness note, per-component
notices in the manifest, verify-notices.sh and notice_resources.py; extended notices_check.py to
validate the generated resources.txt.
Command / exit status: verify-notices.sh --inventory-only -> 0; negative controls -> 1 each
Runtime scene / duration / device-or-Simulator: n/a
Evidence bundle: notices/, docs/native-strikers-dependency-manifest.json
Result: PASS (inventory form); the bundle form awaits a built app
What this result does and does not prove: proves inventory integrity, not ownership or clearance.
Next concrete action: assemble the bundle's notices during packaging and run --final at N7.
```

```text
Phase / gate: N2 (mobile notices packaging)
Date / build identity / patch digest: 2026-09-14; simulator-release configure; series ff01d0f5 at the time (now e13f4db3)
Source invariant and observed failure: the app bundle must carry the tracked notices, and configure
failed with add_custom_command ... TARGET 'strikers' was not created in this directory.
Hypothesis: POST_BUILD may only name a target created in the same directory, and strikers belongs
to the engine port's add_subdirectory, so the app-level call is illegal.
Change: replaced ballpad_bundle_notices()'s POST_BUILD command with an add_custom_target
("${target}_notices" ALL ...) plus add_dependencies in mobile/CMakeLists.txt.
Command / exit status: cmake configure -> 0
Runtime scene / duration / device-or-Simulator: n/a
Evidence bundle: mobile/CMakeLists.txt (ballpad_bundle_notices, ~lines 139-152)
Result: PASS (configure and build proceed); bundle contents not yet verified
What this result does and does not prove: proves the notices step is wired to the app target and no
longer breaks configure; it does not prove the copied notice set is complete.
Next concrete action: run verify-notices.sh --platform simulator against the built bundle.
```

```text
Phase / gate: N1 (desktop runtime unblock: scene-35 SIGSEGV)
Date / build identity / patch digest: 2026-09-14; macos-release @ fork 5b14858; series e13f4db3
Source invariant and observed failure: a driven normal run must not fault in front-end text layout.
Hypothesis (wrong, replaced): STRIKERS_BENCHMARK selected a demo-only timeline asset. The evidence
contradicted it — the fault reproduces without the variable, inside scene 35.
Hypothesis (correct): -fshort-wchar let clang lower wide-string scan loops onto the C library's
32-bit wcslen, so every measured wide-string length came back at roughly half.
Change: -fno-builtin-wcslen added to port_flags in both branches of smstrikers-port/CMakeLists.txt,
keeping -fshort-wchar. Also fixed driver.py, which built a relative STRIKERS_CONTROL path and then
chdir'd into the proof dir, so the guest opened <proof>/<proof>/control.txt and no control line was
ever acked.
Command / exit status: nm -u over 604 port objects -> 0 wcslen refs (was 8; macOS binary relinked
to 12,794,264 B); scenario run -> no crash
Runtime scene / duration / device-or-Simulator: desktop macOS, scene 51 -> 35 -> 27, ~7800 frames,
120 s scene budget; press A 4 acked at frame 604
Evidence bundle: build/proofs/native-strikers/boot-20260914T110414Z/ (also wcsfix-20260914T110205Z/)
Result: PASS (fault eliminated)
What this result does and does not prove: proves the fault is gone and wide-string lengths are
correct on the exercised path; it is not a goal, a replay, or any iOS result.
Next concrete action: drive a full N1 desktop match (menus -> moving match -> goal/replay ->
post-match) without STRIKERS_BENCHMARK, working around the scene-27 save-card popup.
```
```text
Phase / gate: N2 (Simulator link: host zstd leak)
Date / build identity / patch digest: 2026-09-14; fresh simulator-release build dir; series e13f4db3
Source invariant and observed failure: an iOS Simulator link must consume only pinned dependencies,
but the probe link died with `ld: library 'zstd' not found` and Aurora still reported using an
existing zstd.
Hypothesis (wrong, replaced): emptying ENV{PKG_CONFIG_PATH}/ENV{PKG_CONFIG_LIBDIR} isolates the
dependency search. It does not: an empty set(ENV{...}) unsets the variable, so pkgconf fell back to
the Homebrew-only pc_path compiled into /opt/homebrew/bin/pkg-config; and a poisoned build cache
kept a stale ZSTD_FOUND=1 answering with -L/opt/homebrew/opt/zstd/lib -lzstd even after that.
Hypothesis (correct): Aurora must be handed an already-existing zstd::libzstd target so no lookup
runs at all, and a target created in mobile/CMakeLists.txt cannot be inherited from a stale cache.
Change: mobile/CMakeLists.txt now sets the pinned tree's ZSTD_BUILD_* options, add_subdirectory's
<zstd>/build/cmake, asserts libzstd_static, and defines zstd::libzstd as an ALIAS before the port is
added. CMAKE_IGNORE_PREFIX_PATH and FETCHCONTENT_SOURCE_DIR_ZSTD are retained as defence in depth;
the manifest's pins.zstd rationale was corrected to describe the pre-created-target mechanism.
Command / exit status: build.sh --platform simulator --configuration Release --target ballpad_probe
--no-bootstrap (fresh build dir) -> configure 0 in ~380 s; link under way
Runtime scene / duration / device-or-Simulator: n/a (build evidence)
Evidence bundle: build/native/logs/build-simulator-Release.log (current-run region),
build/native/simulator-release/CMakeCache.txt, build.ninja
Result: PASS (configure); link and smoke gate pending
What this result does and does not prove: proves the host zstd answer is gone from the link graph —
no libzstd query, no ZSTD_FOUND/ZSTD_PREFIX/ZSTD_LDFLAGS/pkgcfg_lib_ZSTD_zstd cache entries, no
PkgConfig::ZSTD target, zero lzstd in build.ninja, no -I/-L /opt/homebrew or /usr/local path in
either ninja file, and zstd objects built against the Simulator SDK with -DZSTD_DISABLE_ASM. It does
not prove the app links, launches or presents.
Next concrete action: confirm the probe links, build --target strikers, then run the N2 smoke gate.
```

```text
Phase / gate: N2 (harness: phase logs appended across runs)
Date / build identity / patch digest: 2026-09-14
Source invariant and observed failure: a phase log must describe the run that produced it.
run_logged() used `tee -a` and nothing truncated the file, so
logs/build-simulator-Release.log held six accumulated runs and an earlier run's 'Found libzstd' was
read as the current run's evidence during the zstd diagnosis.
Hypothesis: the stale log, not the toolchain, was producing the misleading evidence.
Change: added log_new() to scripts/native/common.sh, called from build.sh:49, bootstrap.sh:152
(before the first SDL3 run) and verify-clean.sh:196 (before the fresh configure), so a phase log
starts empty.
Command / exit status: bash -n scripts/native/*.sh -> 0
Runtime scene / duration / device-or-Simulator: n/a
Evidence bundle: scripts/native/common.sh (log_new), build.sh:49, bootstrap.sh:152, verify-clean.sh:196
Result: PASS
What this result does and does not prove: proves new runs no longer inherit an earlier run's output.
It does not retroactively validate any conclusion drawn from a pre-fix multi-run log; existing
proof bundles are unchanged.
Next concrete action: cite only current-run log regions as evidence.
```

```text
Phase / gate: N2 (Simulator link: shared libpng resolved through a build-tree rpath)
Date / build identity / patch digest: 2026-09-14; simulator-release; series e13f4db3
Source invariant and observed failure: an iOS bundle must resolve its libraries from itself or
the OS, but BallpadProbe.app carried `@rpath/libpng16.16.dylib` resolved through
LC_RPATH=.../simulator-release/_deps/png-build -- a host build-tree path a device cannot have,
and the same defect the fresh device directory would have inherited.
Hypothesis: Aurora's vendored extern chooses shared over static unless BUILD_SHARED_LIBS is
defined; on iOS the host prefix is ignored, so its find_package(PNG) fallback fails and libpng
is built from the pinned source -- shared -- and the variable is still undefined at that moment
on the first configure of a new build directory.
Change: mobile/CMakeLists.txt:60-81 declares set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
before the port is added, which is what upstream tools/configure.sh passes on the command line.
No script or Python change was needed, and nothing was edited while a script was running.
Command / exit status: cmake reconfigure of build/native/simulator-release -> 0 (configure
73.7 s, generate 6.8 s); fresh-directory configure of build/native/freshcheck-20260914T0855Z
-> 0 (configure 287.9 s); Ninja graph diff between the 06:46 and post-change graphs -> 0
compile edges changed, 24 removed (18 png_shared compiles, 3 dylib edges, 3 phony), 12 changed
link/phony/notices edges, no dawn edge among them
Runtime scene / duration / device-or-Simulator: n/a (build evidence)
Evidence bundle: build/native/freshcheck-20260914T0855Z/build.ninja (png_static only, no
dylib output) and CMakeCache.txt (PNG_SHARED=OFF); build/native/simulator-release/build.ninja;
build/native/logs/build-simulator-Release.log
Result: PASS (configure and fresh-directory proof); rebuilt-bundle and runtime checks pending
What this result does and does not prove: proves that a fresh Simulator or device build
directory now builds libpng static, so no host or build-tree path can enter the bundle that
way, and that the change costs no recompilation (no Dawn object, no source file). It does not
prove the rebuilt bundles launch or present, nor that the device archive links.
Next concrete action: finish the current simulator build, re-run otool -L on both bundles for a
zero host-path and zero @rpath count, then run the N2 smoke gate.
```

```text
Phase / gate: N2 (harness: the built app bundle was never found where the scripts looked)
Date / build identity / patch digest: 2026-09-14; simulator-release; series e13f4db3
Source invariant and observed failure: a script that reports a build or resolves an app bundle must
name the path CMake actually produces. `build.sh --platform simulator` finished the compile and
then died in the post-build platform check, so 'build complete' never printed and the exit status
was nonzero on a correct build; and the smoke suite's `platform.BallpadStrikers.app` row could never
resolve the bundle, so it reported IN_PROGRESS (a failing status) even when the bundle was present.
Both looked for `<build-dir>/BallpadStrikers.app`.
Hypothesis: `strikers` comes from the port's own add_subdirectory(), so CMake places the bundle in
the port's binary directory (`<build-dir>/port/BallpadStrikers.app`), not the build-tree root.
Change: mobile/CMakeLists.txt:264-275 file(GENERATE)s `ballpad-bundles.txt` in the build directory
holding $<TARGET_BUNDLE_DIR:strikers> and $<TARGET_BUNDLE_DIR:ballpad_probe> -- the expression the
notices step already used. scripts/native/build.sh:107-130 reads that file (falling back to the
plain location, then to a bounded find); scripts/native/lib/test_runner.py:232-261 app_path() does
the same.
Command / exit status: build.sh --platform simulator --no-bootstrap -> 0; log line
'platform metadata ok: .../simulator-release/port/BallpadStrikers.app/BallpadStrikers ->
iossimulator'; the generated file reads strikers=.../simulator-release/port/BallpadStrikers.app and
probe=.../simulator-release/BallpadProbe.app.
Runtime scene / duration / device-or-Simulator: n/a (harness/build evidence)
Evidence bundle: mobile/CMakeLists.txt; scripts/native/build.sh; scripts/native/lib/test_runner.py;
build/native/simulator-release/ballpad-bundles.txt; build/native/logs/build-simulator-Release.log
Result: PASS
What this result does and does not prove: proves a correct build now exits 0 and prints its platform
line, and that both bundle paths resolve from the generated file rather than a guess. It does not
prove either bundle launches on a Simulator.
Next concrete action: hand-verify both bundles with vtool/otool, then run the N2 smoke gate.
```

```text
Phase / gate: N2 (the Simulator lock could never be released)
Date / build identity / patch digest: 2026-09-14
Source invariant and observed failure: a held Simulator lock must be released when the run that took
it ends, or the next run inherits a lock nobody holds. sim_lock_acquire (common.sh:184-195) writes
an `owner` file inside `held/`, so test.sh's release step `rmdir "\${SIM_LOCK_DIR}/held"` could never
succeed; and `trap - EXIT` on the line above disabled the `rm -rf` trap that did work, so the lock
was left behind at the end of every run. The next Simulator suite then waited the full 900 s and
died -- exactly what N6's two back-to-back device runs would have hit on the second run.
Hypothesis: the release path, not the Simulator, was leaving the lock held.
Change: scripts/native/test.sh:127-135 now does `rm -rf "\${SIM_LOCK_DIR}/held"` before `trap - EXIT`,
so the release happens while the trap is still armed. No other script changed, and nothing was
edited while a script was running.
Command / exit status: the stale lock was retired recoverably with `mv` to
build/native/sim-lock/held.stale-87064; a subsequent smoke run left build/native/sim-lock/ empty,
proving the release path completes.
Runtime scene / duration / device-or-Simulator: n/a (harness evidence)
Evidence bundle: scripts/native/test.sh:127-135; scripts/native/common.sh:184-195;
build/native/sim-lock/ (empty after a run)
Result: PASS
What this result does and does not prove: proves a finished run no longer leaves the lock held. It
does not prove N6's sequential phone/iPad runs succeed, which is a separate gate.
Next concrete action: re-run the N2 smoke gate now that the lock is not a confounder.
```

```text
Phase / gate: N2 (the Simulator boot budget was treated as a measurement, not a precondition)
Date / build identity / patch digest: 2026-09-14
Source invariant and observed failure: a boot is a precondition for a probe measurement, not the
measurement itself. `simctl bootstatus -b` hit a 300 s deadline under host load 135 and the probe
row reported 'did not reach booted state' -- the host's stall presented as a probe failure.
Hypothesis: the boot budget was too small for a loaded host; the probe row still fails correctly if
the device never comes up.
Change: scripts/native/lib/test_runner.py:333-341 raises boot_device()'s budget 300 s -> 900 s with
that rationale in a comment. The probe's own verdict line is unchanged and still required.
Command / exit status: n/a (budget change)
Runtime scene / duration / device-or-Simulator: n/a
Evidence bundle: scripts/native/lib/test_runner.py:333-341
Result: PASS (budget); whether a boot completes still depends on host memory
What this result does and does not prove: proves a slow boot is no longer misreported as a probe
failure. It does not make the host able to hold a device booted, and it is not evidence of app
health.
Next concrete action: retry the smoke gate; if the host still cannot boot a device, record the
environment blocker rather than a pass.
```

```text
Phase / gate: N2 smoke gate (Simulator probe launch) -- BLOCKED on the shared host
Date / build identity / patch digest: 2026-09-14; simulator-release; series e13f4db3; fork 5b14858
Source invariant and observed failure: the smoke gate passes only when the probe launches under
simctl, presents frames on Metal and exits cleanly with a `[probe] ok frames=N presented=M ...`
line carrying presented > 0. Four of five rows pass; the probe row cannot run because the host
cannot keep a Simulator booted.
Command / exit status: build.sh --platform simulator --no-bootstrap -> 0 (build finished 08:52; the
log ends `[626/627] ballpad: placing third-party notices`; 17 notice files in
port/BallpadStrikers.app/notices). Hand verification of both bundles: BallpadProbe 15,124,256 B and
BallpadStrikers 16,377,744 B; `vtool -show-build` platform IOSSIMULATOR, minos 17.0, sdk 26.5 on
both; `otool -L` shows only /usr/lib and /System/Library with zero host paths, zero `@rpath` and no
LC_RPATH; no .dylib or .so anywhere inside either bundle. Three smoke runs and one manual drive all
failed in the environment, not in the app: smoke-phone-20260914T140511Z (probe row FAIL 'did not
reach booted state'; bootstatus 300 s deadline at load 135), smoke-phone-20260914T141353Z (boot
finished after ~9 min; `simctl install` FAIL code 405 'Unable to lookup in current state: Shutdown',
device shut down externally 09:23:25), smoke-phone-20260914T142437Z (install OK, launch FAIL Mach
error -308 (ipc/mig) server died; device 'Shutting Down' 09:26:41), and /tmp/ballpad-probe-manual-93327
(bootstatus returned `Finished` with the device already 'Shutting Down'; install exit 149, launch
exit 149, device unified log unreachable, EXIT=1).
Runtime scene / duration / device-or-Simulator: iPhone 17e 8619020B-306A-4CA2-B0B3-16C6A3F22472; no
probe frames observed. Host: hw.memsize 24 GiB, vm.swapusage total 0.00M (no swap), 1,238,766-
1,254,979 pages (~19-20 GiB) stored in the compressor, 3,976 pages free (~65 MB), load averages
95-500 on 8 cores; ~/Library/Logs/CoreSimulator/CoreSimulator.log shows the per-boot
SimLaunchHost-arm64 dying each attempt with `(ipc/mig) server died` and 'Invalid device state'.
Evidence bundle: build/proofs/native-strikers/smoke-phone-20260914T140511Z,
smoke-phone-20260914T141353Z and smoke-phone-20260914T142437Z; /tmp/ballpad-probe-manual-run1.log;
/tmp/ballpad-probe-manual-93327/{boot.log,install.log,launch.log,device-log.txt}
Result: BLOCKED (environment) -- neither a probe failure nor a pass
What this result does and does not prove: proves the app and probe are built as IOSSIMULATOR Mach-O
with no host or build-tree linkage, and that the failure is the host's launch service rather than the
app -- there is no crash report for BallpadProbe in ~/Library/Logs/DiagnosticReports/ or in the
device's CrashReporter/ directory. It does not prove the probe launches, presents or exits, so no
Simulator gameplay is claimed for N2.
Next concrete action: retry the gate once the host can hold a device booted (watch `uptime` and the
vm_stat compressor pages first); if it cannot, carry this blocked row forward and advance the
unblocked N1 desktop gameplay capture instead of reporting a timeout as a pass.
```

```text
Phase / gate: N1 (desktop gameplay capture) -- real native-engine match
Date / build identity / patch digest: 2026-09-14; macos-release `build/native/macos-release/strikers`
sha256 e4f244b07121519f697bbeb3e2b1064bac94f0843291d970df36595ffe3bba5d; fork `codex/ios-port` @
5b14858 plus the two log-only input/popup diagnostic edits described below; series e13f4db3
Source invariant and observed failure: a driven desktop run must pass through the front end without
hand-holding and reach a match whose clock advances and whose score can change -- i.e. real gameplay,
not a rendered menu. Earlier runs stalled on scene 27's memcard popup.
Hypothesis: the stall was not an input race, a gate or a lost press. The front end really is a fixed
chain of screens, each with its own pre-input lock and its own slide gate, and the route needs one
press per screen rather than one press per route (see `### 8. Hypothesis log`, hypotheses 9-12).
Change: no gameplay change. Two env-gated, log-only, `// PORT:`-marked diagnostics were added so the
engine can be measured instead of guessed at: `src/Game/FE/fePopupMenu.cpp` logs popup state (created,
displayed, accept-delay, option count, slide time/start/duration, live A edge) as the first statement
of `FEPopupMenu::Update`, and `src/NL/plat/platpad.cpp` logs the pad's category, error and
just-pressed/released edges immediately before `if (resetMask)` in `PadStatus::Update`. Both are
diagnostic only and change no behaviour.
Command / exit status: `python3 scripts/native/lib/driver.py --suite n1-explore --platform macos ...`
-> exit 0; engine exit status 0. Route scenario `/tmp/scn-nav-v12.scn`.
Runtime scene / duration / device-or-Simulator: macOS desktop (M2), Release, ~153 s wall for the run.
The route is 51 health -> 35 saving_loading -> 39 englegal -> 53 intro movie -> 2 title -> 3 main menu
-> 1 mariobg background -> 8 choose_captains_v3 (captains AND sides) -> 9 choose_stadiums_v2 -> 43
super loading -> overlays 68/67/72/77 (a real match: HUD, text, goal, winner). Match telemetry from the
in-engine dump: `valid=1`, `dur=300.0`, `skill=1`, `pads=0,-1,-1,-1` (one human on side 0), clock
advancing 0.00 -> 7.82 -> 17.81 -> 37.83 -> 57.88 -> 58.01 -> 75.69 s, and the score moving 0-0 ->
0-1 at frame 7803 (frame 5400 is still 0-0). Frames s8/s9 show Mario vs Luigi with the live HUD,
clock, team banners, shadows, the AI Toads and the ball, not a static menu.
Evidence bundle: build/proofs/native-strikers/n1-nav-v9 (save present, popup skipped),
n1-nav-v10 (full FE route to captains), n1-nav-v11 (scene-8 phase machine returns POPUP_NO_SIDES_CHOSEN
as designed), n1-nav-v12 (the match; shots/s8.ppm and shots/s9.ppm); n1-nav-v7 and n1-nav-v8 (the
popup-accept and control-channel measurements), plus v1-v6 for the earlier exploration.
Result: PASS -- real native-engine gameplay on the desktop reference build.
What this result does and does not prove: proves the native port boots through the front end, builds a
match, advances its clock, resolves a goal and renders the match. It is desktop (macOS, M2) evidence:
it does not prove Simulator or device behaviour, frame rate under the iOS frame-owner, audio
correctness, save persistence across launches, or endurance. The scene transitions at frame 0 in
result.json are real transitions recorded before the driver's first acknowledgement line, not a
harness error: the driver only starts reading stderr after launch, and the first ack (frame ~1803)
flushes the earlier buffered scene lines.
Next concrete action: carry the same route onto the Simulator under the iOS frame owner (N3).
```

```text
Phase / gate: N2 (Simulator smoke gate) -- probe row finally unblocked
Date / build identity / patch digest: 2026-09-14; simulator Release bundles under
build/native/simulator-release; fork tree and series unchanged from the previous checkpoint (the two
diagnostics above are the only engine delta since 85429409e13cc517af7803b2d1101785a9128318)
Source invariant and observed failure: the smoke suite passes only when the probe launches under
simctl, presents frames on Metal and exits cleanly. Four of five rows passed; the probe row died in the
host every attempt with `(ipc/mig) server died` while the machine carried load averages of 95-500 and
~20 GiB in the VM compressor.
Hypothesis: the blocked row was the host, not the app. The same machine at load 28 should boot, install
and launch.
Change: none to the app or the test; the gate was simply re-run on a quieter host.
Command / exit status: `./scripts/native/test.sh --suite smoke --device
8619020B-306A-4CA2-B0B3-16C6A3F22472 --run-id smoke-phone-retry1` -> exit 0
Runtime scene / duration / device-or-Simulator: iPhone 17e Simulator 8619020B-306A-4CA2-B0B3-16C6A3F22472,
Release. All five rows PASS; the probe row reads `probe presented 90/90 frames on backend metal and
exited cleanly`, alongside the two platform rows (both bundles IOSSIMULATOR) and the two linkage rows
(23 SDK/system libraries, no Homebrew or /usr/local path).
Evidence bundle: build/proofs/native-strikers/smoke-phone-smoke-phone-retry1/
Result: PASS -- the N2 smoke gate is complete, all five rows.
What this result does and does not prove: proves the Simulator bundles are correctly targeted and
linked, and that the minimal app can bring up a drawable, present 90 frames on Metal and exit cleanly
under the Simulator. It does not prove the full game runs on the Simulator -- that is N3.
Next concrete action: N3 -- drive BallpadStrikers.app itself (not the probe) on the Simulator through
the same front-end route to a real match, then build the device platform.
```

```text
Phase / gate: N3 -- complete native Simulator match, goal, goal presentation and automatic replay
Date / build identity / patch digest: 2026-09-14; simulator-release, port/BallpadStrikers.app
  sha256 e8a1a0c5241d46f2ca06ca6ba78aff1b4ca6889a05cbacc18c316ff11ffc475f; engine fork 431de3bb,
  tree f7dbf197 clean; patch series 51a1ec62; disc da80883b (the recorded baseline)
Source invariant and observed failure: the port must play a real match on the Simulator under the
  iOS frame owner, with the goal, its presentation and the replay all coming from the engine rather
  than from the harness. Observed failure: the first scenario stalled for its full 420 s budget
  before live play. The anchor was `wait-log [match] state=4 ot=0 score 0-0`, but the engine emits
  `[match] t=0.7/300.0 state=4 ot=0 score 0-0 ball=(...)` -- `t=` and `ball=` sit between the tag
  and `state=`, so that needle matches nothing, ever. A second, separate defect made the failure
  look intermittent: `wait-log` could consume a line an earlier run had already written to the
  reused log, so a wait could resolve instantly against stale evidence.
Hypothesis: the replay could not be sampled by predicting a frame, because the control heartbeat is
  600 frames -- longer than the replay lasts -- so a frame-anchored sample would miss it entirely.
  The engine already publishes the states that matter as periodic lines; anchor on those instead,
  and let the match score on its own rather than injecting a goal.
Change: `wait-log` now skips lines already present when the step begins. The scenario was rewritten
  to anchor on the always-present goalless live-play line and then to walk the engine's own state
  lines: `state=0x100` (presentation/NIS) for the goal celebration, `0x10` (auto replay) four
  times for four replay samples, `0x2` for the return to play. Nothing is injected: the goal is
  whatever the match scores, and the engine's detection, scorer credit, celebration script and
  `PlayAutoReplay(REPLAY_TYPE_GOAL)` all follow from it. The dead injection path is documented in
  the scenario's own comment as a fallback (`PDBG_WARP_BALL`, op 8, the same request the debug
  menu's "into home net" button sends) and is not used. The new runner also seeds the memory card
  the front end needs to skip its popup, and `run-scenario.sh` itself was fixed after dying
  instantly on its own `--run-id` (see the current-state notes).
Command / exit status: `./scripts/native/run-scenario.sh --scenario n3-sim-replay --run-id
  n3-sim-replay-r1 --device 8619020B-306A-4CA2-B0B3-16C6A3F22472 --budget 1500` -> exit 0
Runtime scene / duration / device-or-Simulator: iPhone 17e Simulator 8619020B-306A-4CA2-B0B3-16C6A3F22472,
  Release. 145.2 s wall for the whole route and 31 driver steps, every ack in order, no crash. The
  dumps read: kickoff task=2 state=4 score 0-0 clock 0.77; postgoal task=2 state=2 score 0-1 clock
  10.93; goal_pres task=256 score 0-1; replay0-3 task=16 state=2; back_to_play task=2 state=1;
  middlegame task=2 state=4 score 0-2 clock 55.51, at frame 9004. The log shows the match begin,
  the goal at t=10.9, `[nis] toad_goal_winner_high_0.nis` for the celebration, and the replay task
  holding from frame 4136 to 4450 before returning to live play.
Evidence bundle: build/proofs/native-strikers/n3-sim-replay-phone-n3-sim-replay-r1/ -- result.json
  (S.run PASS, S.provenance PASS), driver-result.json (verdict PASS, 9 dumps, 8 captures),
  driver.log, app.log, metadata.json, the seeded user/ card and a copy of the scenario.
Result: PASS
What this result does and does not prove: proves the native engine runs a real match on the
  Simulator end to end -- front end to live play to goal to presentation to automatic replay and
  back -- driven by real input and the port's own frame scheduling, with the goal coming from the
  match rather than from the harness. It does not prove device behaviour, frame rate, audio, or the
  doc 34 performance and endurance rows; none of those are claimed here, and the limiter's
  `63.00 Hz` line is a target, not a measurement. It also does not prove the goal-injection path,
  which this run never exercised.
Next concrete action: build the device platform (`bootstrap.sh --platform device`, then
  `build.sh --platform device`) and assert an unsigned Mach-O with platform 2 and no host leakage
  before N4 integrates Ballpad's interface.
```

```text
Phase / gate: N2 -- device platform dependencies and the device app archive (N2 closes here)
Date / build identity / patch digest: 2026-09-14/15; bootstrap run 20260915T010825Z; engine fork
  431de3bb, tree f7dbf197 clean; patch series 51a1ec62; disc da80883b (the recorded baseline)
Source invariant and observed failure: the runbook requires an unsigned iOS device build whose
  platform metadata is genuinely iOS and whose linkage could be satisfied by a device. Observed
  state going in: only the Simulator dependency set existed, so nothing proved that the port's
  dependencies, Dawn in particular, could be built for `iphoneos` at all.
Hypothesis: the Simulator work would carry over unchanged, because the only platform-specific
  inputs are the sysroot, the target triple and the per-platform dependency output directory --
  Dawn is already built from source because no upstream prebuilt slice exists for Apple mobile.
Change: none to the port. `bootstrap.sh --platform device` staged SDL3 and FFmpeg for
  `iphoneos` and reused the already-extracted pinned Dawn source; `build.sh --platform device
  --no-bootstrap` then configured and built Dawn plus the app for the device sysroot.
Command / exit status: `./scripts/native/bootstrap.sh --platform device` -> exit 0 (run id
  20260915T010825Z); `./scripts/native/build.sh --platform device --no-bootstrap` -> exit 0,
  `platform metadata ok: ... BallpadStrikers -> ios`
Runtime scene / duration / device-or-Simulator: build only, no runtime. Verified on the artifact:
  arm64, `platform IOS`, minos 17.0, sdk 26.5, 16,152,240 B, sha256
  cca8f62dac775d48b60ff28444b0bfeba8aa6110c4979c6624f43bd0d7a1d38e; 21 loaded libraries, every
  one an SDK framework or system library (`/System/Library/...`, `/usr/lib/...`), no `LC_RPATH`
  at all, and `codesign -dv` reports "code object is not signed at all" -- unsigned, as required.
  The probe app asserts platform IOS too (sha256 01850438fa35c13a15f2ccc6b34cc17e7c0ca6257f70e6bbbca29b89dc97bd81).
  The bundle carries 17 notice resources and no icon or image of any kind.
Evidence bundle: build/native/device-release/ (a build output, not a proof bundle); logs
  `build/native/logs/bootstrap-sdl3-device.log`, `bootstrap-ffmpeg-device.log` and the build log
Result: PASS -- N2's device half is closed. Device runtime behaviour is untested and unclaimed.
What this result does and does not prove: proves the dependency set builds for `iphoneos` from the
  same pins, and that the resulting archive is an unsigned arm64 iOS binary that links only SDK and
  system libraries -- so a device could load it once it is signed. It does not prove anything runs
  on a device, and it does not prove the device code path behaves like the Simulator. No hardware
  is present in this task, so device validation stays open by design.
  Honest detail recorded rather than rounded off: the binary embeds 233 absolute source-path
  literals under `/Users/chrissotraidis/GitHub/ballpad/work/...` from `__FILE__` in port and ODE
  sources. There is no `__debug_info` section, so these are not DWARF, and they are not linkage
  paths -- the existing host-link check poisons `/opt/homebrew`, `/usr/local` and `/opt/local`
  and none is present. They disclose the builder's directory layout, so `-ffile-prefix-map` is
  worth adding before any public distribution; it is not a blocker for this development build.
Next concrete action: N4 -- integrate Ballpad's interface over the native port, beginning with R1
  (adopt SunPad's three-dot menu and GameCube controls) while the device archive stays as the
  artifact for N7.
```

```text
Phase / gate: N4-A + N4-B -- vendor SunPad's interface, compile it, then bridge it into the port
Date / build identity / patch digest: 2026-09-14/15; engine fork 450e5c00, tree 15061aa2 clean;
  patch series 0e902174 (6 patches); app binary 34dd7109, 16,550,496 B, Simulator Release
Source invariant and observed failure: doc 36 R1 requires SunPad's GameCube controls and its
  three-dot menu adopted as they are, publishing touch state through SunPadInputMixer into the
  port's pad. The open question going in was the input path: whether the port needed a new private
  hook, or whether Aurora's published channel already carries a host-supplied pad.
Hypothesis: Aurora's public PADSetVirtualStatus is enough, because PADRead already runs in this
  port and merge_virtual_status() (extern/aurora/.../pad/pad.cpp:699-710) merges a virtual pad with
  a physical controller rather than replacing it -- buttons OR'ed, the larger-magnitude axis wins,
  triggers maxed. If that holds, touch and a real controller can both be live and no Aurora change
  is needed at all.
Change: N4-A -- the nine files named in the plan of record copied byte-for-byte into
  mobile/interface/sunpad/ and compiled as the 'ballpad_interface' static library (the four .mm
  files under -fobjc-arc, linking UIKit/Foundation/GameController/QuartzCore). N4-B -- a port-side
  seam (include/port/hostui.h, weak no-ops in src/platform/hostui.c, the calls in src/Game/main.cpp
  and the merge in src/platform/input.cpp) plus the app-side adapter
  mobile/interface/BallpadHostUI.mm, built as 'ballpad_hostui', which creates the overlay, reads
  SunPadInputMixer once per frame and translates SunPad's mask into PORT_PAD_* names.
Command / exit status: build.sh --platform simulator --no-bootstrap -> 0;
  export-patches.sh -> 0 ('series reproduces the fork tree exactly (15061aa2)');
  run-scenario.sh --scenario n4b-hostui-seam --run-id n4b-hostui-seam-r2 -> 0
Runtime scene / duration / device-or-Simulator: iPhone 17e Simulator; health-and-safety screen to
  frame ~600 for the seam run, plus a driven touch test against the live memory-card screen
Evidence bundle: build/proofs/native-strikers/n4b-hostui-seam-phone-n4b-hostui-seam-r2/ -- driver
  verdict PASS, S.run and S.provenance both PASS, and simshots/ holding the interface over a real
  game frame, the open three-dot menu, and a before/after pair for the touch test. Regression
  bundle build/proofs/native-strikers/n3-sim-replay-phone-n3-regress-after-n4b/ -- the whole N3
  route still PASSes with the merge in place.
Result: PASS -- N4-A and N4-B are complete. N4-C and N4-D are open.
What this result does and does not prove: proves the vendored set is self-contained on this
  toolchain and is the interface actually running -- the nine vendored files still hash exactly to
  the table in mobile/interface/sunpad/README.md, so the geometry under review is the sibling
  project's bytes rather than a retyping. Proves the port calls into the app: 'host ui: overlay
  {{0, 0}, {844, 390}} over <SDL_uikitmetalview ...>' is printed once from PortHostUIStart, and
  'host ui: first pad poll' can only come from inside the frame loop, so the port is driving this
  adapter rather than its own weak no-op (the trap in hypothesis 15). Proves input is consumed by
  the game rather than merely drawn: tapping the overlay's A button on the memory-card screen
  advanced it to the 'will automatically save to the Memory Card in Slot A' screen, 183,811 pixels
  changed between the pair, and the Simulator's accessibility tree exposes Menu, START, L, R, the
  four D-pad arrows and A/B/X/Y/Z -- SunPad's control set -- as real elements. The three-dot menu
  opens SunPad's own action list (Render Resolution, Aspect Ratio, Show FPS Counter, Experimental
  Performance Mode, Experimental 60 FPS, Controller Button Mapping..., the last four carrying the
  (Restart Required) and mapping rows the overlay ships).
  Does not prove: the doc 33 N4 gate itself. The overlay's placement and relayout are unaudited,
  the four delegate actions still only log (they are N4-C), settings persistence, layout reset and
  pause-with-input-release are unexercised, and nothing here has run on an iPad. It also does not
  prove the game is playing correctly with touch -- only that one real tap reached the engine and
  changed its state. The menu title still reads "SunPad" in the vendored header, which N4-C must
  resolve deliberately rather than by editing a file the fidelity claim depends on.
Next concrete action: N4-C -- place the overlay correctly over the render surface on both form
  factors, relayout on rotation and safe-area change, release input on pause, confirm settings
  persistence and layout reset, route the four delegate actions to Ballpad's own importer, settings
  store and diagnostics, and decide the menu-title question without touching the vendored bytes.
```

```text
Phase / gate: N4-C (host/lifecycle surface) + N4-D (doc 33 gate) -- the interface half, both form factors
Date / build identity / patch digest: 2026-09-14; engine fork 450e5c0047fa, tree 15061aa2 clean;
  patch series 0e902174 (6 patches); app binary 5b22cec45b79, 16,551,648 B, Simulator Release;
  test bundle a00fd3af89a7 (identical on both destinations)
Source invariant and observed failure: doc 36 R1 requires SunPad's three-dot menu, its touch-control
  settings surface and its layout persistence adopted as they are and *exercised through the real
  surface* on phone and iPad. Going in, only the open-menu geometry had been observed, on the
  phone, and the whole suite failed on the phone while passing on the iPad -- with the same
  build and the same vendored bytes, which is exactly the shape of an unexplained form-factor gap.
Hypothesis (resolved as 17): the phone failure was not a missing row. A `UIMenu`'s presentation is
  iOS's, and the panel it grants is smaller on a compact-width phone, so the menu scrolls and its
  below-the-fold cells are not in the accessibility tree -- while the vendored menu the app builds
  is identical on both idioms.
Change: (1) the suite walks the menu with bounded scrolls, recording each row's first sighting and
  its vertical position, and asserts every vendored row is reachable and first sighted in vendored
  order, instead of requiring all nine to be published at once; (2) `attachHierarchy` keeps the
  runner's own element tree with each claim, so "absent" and "below the fold" stop looking alike;
  (3) `preflight()` writes device, app path and hash, seed, boot, install and the *installed*
  binary's hash into `preflight.log` inside the bundle, because `log_new "$LOG"` had been
  truncating every line decided before `build-for-testing` (hypothesis 18). No vendored byte and no
  app source changed for any of this.
Command / exit status: `scripts/native/run-uitests.sh --run-id n4d-phone-uitest-r2 --device
  8619020B-... --form-factor phone --budget 1500` -> exit 0; same with `--run-id n4d-pad-uitest-r3
  --device B3799189-... --form-factor pad` -> exit 0
Runtime scene / duration / device-or-Simulator: iPhone 17e and iPad (A16) Simulators, both in
  landscape, both from the seeded memory card so the overlay is judged over the real front end
  rather than over a popup. Phone 5 tests in 366 s (40.5 / 107.3 / 88.3 / 29.2 / 100.1); pad 5
  tests in 200 s (22.4 / 55.6 / 35.8 / 39.0 / 47.5)
Evidence bundle: build/proofs/native-strikers/uitest-phone-n4d-phone-uitest-r2/ and
  build/proofs/native-strikers/uitest-pad-n4d-pad-uitest-r3/ -- each with `result.json`, `rows.tsv`,
  `preflight.log`, the `.xcresult`, exported screenshots and the two element trees per menu claim
Result: PASS for the interface half of N4-C and N4-D, on both form factors. The N4 gate itself is
  NOT claimed: its Files-import half is open, and so is the phone half of the N4-D match run.
What this result does and does not prove: proves the vendored menu publishes all nine rows in
  vendored order on both devices, that the settings panel and its layout editor are reachable and
  answer through real touches, that a render-scale choice and a dragged control position both
  survive a terminate-and-relaunch (a fresh process reading the same domain, so this is persistence
  and not in-process state), that the vendored reset alert restores the default and that the reset
  itself survives a relaunch, and that the overlay and its menu still open after a background /
  foreground cycle. Also proves the suite drove the current build: `installed binary
  5b22cec45b79...` out of the Simulator's own container equals the build-tree `app binary
  5b22cec45b79...`, which an earlier bundle could not show at all. Does not prove: that any setting
  reaches the renderer (item 5 of the R1 to-do list -- persistence and effect are different claims),
  that the menu's data/removal rows route anywhere (they are log-only until N5), that rotation
  relayout is correct (both suites run landscape only, so F06's orientation half is unexercised),
  that the engine consumed any of these touches as gameplay input (these rows are interface claims;
  F04 is the row that requires game response), or anything about audio.
Next concrete action: N5's first work item, which is also what closes N4-D -- Ballpad's own Files
  importer, starting from the pre-`main()` `DVDInit()` ordering problem the N4-C/N5 split was
  created for. Then F04's per-control touch drive and F06's rotated relayout.
```

```text
Phase / gate: N4-D -- the doc 33 match half, iPad
Date / build identity / patch digest: 2026-09-14; engine fork 450e5c0047fa, tree 15061aa2 clean;
  patch series 0e902174; app binary 5b22cec45b79, Simulator Release; disc da80883ba456
Source invariant and observed failure: N3's whole-route evidence existed on the phone only, and
  doc 34's matrix applies to both form factors. Nothing about the port is phone-specific, so the
  iPad run is a repeat of the same scored route rather than a new mechanism.
Hypothesis: the recorded route is form-factor independent, because the port drives its own
  synthetic pad and the renderer scales the drawable rather than branching on idiom.
Change: none. The N3 scenario was replayed on the iPad destination with the same seed and the same
  control route: `scripts/native/run-scenario.sh --scenario n3-sim-replay --run-id
  n4d-ipad-match-r1 --device B3799189-... --form-factor pad --budget 1500`
Command / exit status: exit 0; driver verdict PASS over 31 steps, `S.run` and `S.provenance` PASS
Runtime scene / duration / device-or-Simulator: iPad (A16) Simulator, landscape, ~150 s wall,
  frames to 9007; kickoff (clock 0.78, 0-0, state 4) -> postgoal (13.86, 0-1, state 2) -> goal
  presentation (task 256) -> four replay samples (task 16) -> back to play -> middlegame
Evidence bundle: build/proofs/native-strikers/n3-sim-replay-pad-n4d-ipad-match-r1/ -- 8 frame
  captures, 9 state dumps, driver.log, app.log, metadata.json
Result: PASS
What this result does and does not prove: proves the same native-engine scored route (front end to
  live play, an engine-detected goal, automatic replay, return to play) reaches the iPad on the
  current build, with render size 1180x820, and that goal and replay frames are visually coherent
  on inspection -- the goal presentation shows the 0-0 clock at 4:46 with the ball in the net, and
  a replay frame carries the game's own `R` indicator. Does not prove: anything about touch input
  on the iPad (this route uses the port's synthetic pad, not the overlay), or iPad performance.
  One honest artifact, hypothesis 16, since superseded by measurement: the kickoff sample -- frame
  3232, the first live-play frame, `state=4 t=0.7` -- captured a 100% black framebuffer (mean 0.0)
  while every other sample in the same bundle is lit. This bundle's "fading in" reading of that
  sample was wrong: the dense re-run `n4d-dense-r2` captured frame 3232 lit at mean 92.9252 among
  278 consecutive lit frames, and the desktop `n1-nav-v12` bundle holds a black frame 7.82 s into
  live play where no fade exists. The mechanism is a capture-path race, not a transition; see the
  rewritten hypothesis 16. Nothing here is a stall, and no pixel assertion in this ledger relies on
  the capture path or on a frame taken during a wipe or a scene transition.
Next concrete action: repeat the same route on the phone on the current build, then take up N5's
  first work item.
```

```text
Phase / gate: N4-D -- the doc 33 match half, phone, on the current build
Date / build identity / patch digest: 2026-09-15T04:00Z (2026-09-14 local); engine fork
  450e5c0047fa, tree 15061aa28d04 clean; patch series 0e902174 (6 patches); app binary
  5b22cec45b79, 16,551,648 B, Simulator Release; disc da80883ba456
Source invariant and observed failure: the iPad match half passed, but the phone half of N4-D was
  still the N3 run on an earlier fork and an earlier app, so the two form factors did not carry
  the same claim on the same build -- and doc 34's matrix applies to both.
Hypothesis: the recorded route is form-factor independent, because the scenario drives the port's
  own synthetic pad and the renderer scales the drawable rather than branching on idiom.
Change: none. Same scenario, same seed, phone destination:
  `scripts/native/run-scenario.sh --scenario n3-sim-replay --run-id n4d-phone-match-r2 --device
  8619020B-... --form-factor phone --budget 1500`
Command / exit status: exit 0; driver verdict PASS over 31 steps; `S.run` and `S.provenance` PASS
Runtime scene / duration / device-or-Simulator: iPhone 17e Simulator, landscape, 169.4 s wall,
  8 frame captures, 9 state dumps, frames to 9006. Dump sequence: kickoff `state=4 clock=0.73 0-0
  pres=Idle` -> postgoal `state=2 clock=27.54 0-1 pres=GoalCaptainCelebration` -> goal presentation
  (same state and clock, `pres_t=0.98`) -> replay0/1/2 (same clock, replay) -> replay3 `state=2
  clock=55.39 0-2 pres=GoalSidekickCelebration` -> back to play `state=1 clock=55.39 0-2 pres=Idle`
  -> middlegame `state=2 clock=73.16 0-3 pres=GoalSidekickCelebration`. Shot/dump frames
  3155/3159, 4491/4493, 4502/4504, 4657/4659, 4686/4688, 4807/4809, 6816/6818, 7109/7111, 9002.
Evidence bundle: build/proofs/native-strikers/n3-sim-replay-phone-n4d-phone-match-r2/ --
  result.json, rows.tsv, driver.log, app.log, metadata.json and shots/ (8 .ppm)
Result: PASS -- the phone half of the N4-D match gate closes, so both form factors now carry the
  same scored route on the same build.
What this result does and does not prove: proves the whole native-engine route on the phone on the
  current build -- front end to live play, an engine-detected goal, scorer credit, the goal
  presentation, the automatic replay and the return to play -- and that it scores *more* than once
  (0-0 -> 0-1 at clock 27.5, 0-2 at 55.4, 0-3 by 73.2), which is evidence that play continues
  rather than stopping at the first goal. One honest artifact, now explained rather than smoothed
  over: this bundle's `kickoff.ppm` is the 100% black sample (mean 0.00, 970x448) and its
  `goal.ppm` is unusually dark but lit (mean 22.41, 76.5% of pixels at 0). The black one is the
  same capture-path race hypothesis 16 now names, not a fade -- see the two capture checkpoints
  below, which measured it directly on this build and on the desktop. Does not prove: anything
  about touch input (this route uses the port's synthetic pad, not the overlay), or phone
  performance.
Next concrete action: settle the black-frame question by measurement rather than by reading one
  more sample.
```

```text
Phase / gate: N4-D -- capture-path diagnostic, bounded consecutive-frame burst (the black-frame
  question, part 1 of 2)
Date / build identity / patch digest: 2026-09-15T04:16Z (2026-09-14 local); engine fork
  3f7b48cb5cea, tree 51b07cdfbaee clean; patch series 561efa8ca80f (7 patches); app binary
  30f2d3eb13ca, 16,551,648 B, Simulator Release
Source invariant and observed failure: the iPad match checkpoint recorded a 100% black first
  live-play frame and read it as a fade, and the phone match bundle reproduced the same black
  without a fade. Three readings were still live: a fade in, a genuine one-frame presented flash,
  or a readback race in the port's own capture path. A single sample cannot separate them, and the
  frame number is drift-prone because the front end's presses are anchored to scene-entry lines
  that are themselves polled.
Hypothesis: capturing *every* consecutive frame across the whole transition window answers the
  question, because a fade is a monotone ramp, a flash is an isolated black frame bounded by lit
  ones, and a readback race either lands off a frame boundary or repeats a neighbour's content.
Change: a bounded burst mode for the port's capture path -- `STRIKERS_CAPTURE_FROM` /
  `STRIKERS_CAPTURE_TO` on top of the existing `STRIKERS_CAPTURE_EVERY`, so the run writes one file
  per frame only inside the window instead of from frame 0. Committed to the fork as `3f7b48c`
  ("port: bound the frame burst to STRIKERS_CAPTURE_FROM/TO"), which is why the series moved from
  6 to 7 patches. New scenario `tests/native/scenarios/n4d-kickoff-dense.scn` spans 3080..3360.
Command / exit status: `run-scenario.sh --scenario n4d-kickoff-dense --run-id n4d-dense-r2 --device
  8619020B-... --form-factor phone --budget 600` -> exit 0; `S.run` and `S.provenance` PASS
Runtime scene / duration / device-or-Simulator: iPhone 17e Simulator, 59.6 s wall; 278 of the 281
  window frames written, all 970x448. Frame means 92.0054..93.0904; **zero black frames at
  `--black 0` and zero at `--black 8`**; worst dark-pixel fraction 0.19% at `--black 0` (0.30% at
  `--black 8`). Burst indices 1, 208 and 245 are the only gaps. Frame 3232 -- the historically
  black first live-play frame -- reads mean 92.9252, flanked by 92.9043 and 92.9129. The engine's
  `[match] ... state=4` line falls between burst index 151 (frame 3231) and 152 (frame 3232). The
  only structure anywhere is a shallow dip to 92.0054 at frame 3155, which is the *other*
  historically black frame, and it reads as a local minimum recovering to 92.07 by 3175 rather than
  as a ramp.
Evidence bundle: build/proofs/native-strikers/n4d-kickoff-dense-phone-n4d-dense-r2/ -- result.json,
  rows.tsv, metadata.json, app.log, driver.log and the three derived artifacts `frame-stats.csv`,
  `frame-stats.txt` (`--black 0`) and `frame-stats-black8.txt`
Result: PASS. Two of the three readings are refuted by this run: there is no ramp out of black (so
  not a fade) and there is no isolated black frame at the transition (so not a presented one-frame
  flash in the still path); a genuinely visible flash of one frame remains possible but unsupported.
  Companion run `n4d-kickoff-fade-r1` -- nine shots taken immediately after the engine's live-play
  line, means 92.79..92.95, no black sample at all -- says the same thing about the frames *after*
  the transition. Earlier attempt `n4d-dense-r1` produced the same kind of burst but failed its own
  `S.provenance` row because the port had an uncommitted `main.cpp` edit the series did not carry;
  it was superseded by `r2` once that work was committed as `3f7b48c`. `frame_stats.py` gained a
  numpy fast path for this run, verified histogram-for-histogram against the `bytes.count` fallback
  on four frames, because 278 frames through the pure-Python path takes minutes against about two
  seconds.
What this result does and does not prove: proves the black sample is a capture-path artifact and
  not a transition in the rendered game, on this build and this device, with the window wide enough
  that a missed frame number cannot explain it. Also fixes the tooling used to say so, and records
  that the port's capture path is not a pixel oracle for a single frame. Does not prove the game
  never flashes black *inside* the presented surface -- the still path cannot see that, which is
  what the video run answers. New hypothesis 19 came out of this run and is recorded in the
  hypothesis log: a dense burst scrambles the capture log-to-file accounting, so `Wrote frame
  capture` must not be read as a capture count. Measured here: 281 `[shot]` lines over 281 distinct
  paths, 281 `Wrote` lines over only 271 distinct paths (10 paths written twice), 278 files on
  disk, 9 on-disk files with no `Wrote` line, 10 paths with a `[shot]` line but no `Wrote` line,
  and two paths (208, 245) with both lines and no file.
Next concrete action: take the one measurement the still path structurally cannot make -- record
  the actual presented surface over the same instant and look for a black frame there.
```

```text
Phase / gate: N4-D -- capture-path diagnostic, screen recording vs still (the black-frame
  question, part 2 of 2 -- closes it)
Date / build identity / patch digest: 2026-09-15T04:23Z (2026-09-14 local); engine fork
  3f7b48cb5cea, tree 51b07cdfbaee clean; patch series 561efa8ca80f (7 patches); app binary
  30f2d3eb13ca, Simulator Release
Source invariant and observed failure: the dense burst closed the still path's artifact but could
  not say what the *presented* surface did at that instant, because the same capture path is what
  produced both the black sample and its lit neighbours.
Hypothesis: recording the Simulator's own output while a still is taken at the same instant will
  separate a real presented flash from a readback race: a flash appears in the recording as a black
  frame, a race does not.
Change: none to the app. A new scenario `tests/native/scenarios/n4d-kickoff-video.scn` takes a
  still immediately after the same `wait-log state=4 ot=0 score` step, and `xcrun simctl io <udid>
  recordVideo --codec h264` was run alongside it, so the still and the recording describe one
  instant rather than two nearby ones.
Command / exit status: `run-scenario.sh --scenario n4d-kickoff-video --run-id n4d-video-r1 --device
  8619020B-... --form-factor phone --budget 600` -> exit 0 (driver PASS, `S.run` and `S.provenance`
  PASS) with `simctl io recordVideo` running concurrently; the trailing implicit `quit` step hung
  teardown again, which is the known harness defect and not evidence.
Runtime scene / duration / device-or-Simulator: iPhone 17e Simulator; 60.7 s scenario wall and a
  67.9 s recording at 1170x2532, 3857 frames, ~56.8 fps. This run's own still was *lit* (92.94) --
  the race did not reproduce -- which is exactly why the recording, not the still, is the evidence.
  `ffmpeg -vf blackframe=amount=90:threshold=10` over the whole recording found **zero frames**.
  Per-frame average luma (`signalstats`, 3857 frames parsed) has a minimum of 16.0, reached at
  frames 92-101 and 3814-3817, and only 14 frames anywhere below 20. Luma 16 is the video-standard
  black level, so the compositor never presented a fully black surface. The recorder emitted many
  `non monotonically increasing dts` warnings (duplicate timestamps); they are harmless to the
  luma reading and are noted rather than suppressed.
Evidence bundle: build/proofs/native-strikers/n4d-kickoff-video-phone-n4d-video-r1/ -- result.json,
  rows.tsv, metadata.json, app.log, driver.log, shots/kickoff-v.ppm. The recording itself is
  game-derived and stays out of the repository: /tmp/ballpad-kickoff-video-r1.mp4, with the parsed
  per-frame luma in /tmp/ballpad-yavg-r1.txt.
Result: PASS. The black-frame question is **closed, as a capture-path artifact**. The desktop
  bundle `n1-nav-v12` already refuted the fade from the other side -- it holds a black still at
  frame 3606 whose own dump at frame 3602 reads `state=4 clock=7.82 pres_t=11.87`, i.e. 7.82 s into
  live play where no fade exists -- and `aurora.cpp end_frame()`'s ordering shows the capture is
  not simply racing the same encoder. So the artifact is the readback path, wherever the still path
  was used: the iPad bundle that raised it, the phone dense and fade runs, and the desktop
  reference.
What this result does and does not prove: proves no fully black frame reached the presented
  surface during this run, which is what the still path could not show. Does not prove the engine
  never renders a black frame internally, or that a one-frame flash is impossible in some other
  scene; it removes the specific hypothesis from the kickoff transition this evidence was built
  around. It also does not prove anything about audio -- that is R2, which stays unrun.
Next concrete action: stop spending runs on the capture path and take up N5's first work item --
  Ballpad's own Files importer, starting from the pre-`main()` `DVDInit()` ordering problem --
  alongside the R1 to-do list's remaining rows and R2's audio measurement path.
```

+```text
Phase / gate: N4 -> N5 (the port's disc seam, and a crash on the way out of a failed start)
Date / build identity / patch digest: 2026-09-15; engine fork c28a6d7, tree 15d79868 clean; patch
  series bc19ccd92c75 (9 patches); macos-release/strikers sha256 5f9a1a1b93f2; simulator-release
  app binary 7e526c45f9b6; disc da80883ba456 (the recorded baseline)
Source invariant and observed failure: N4's Files-import half needs the port to reach its entry
  point without a disc and let the host supply one, but the port resolved its disc from a static
  initialiser (nlMalloc -> nlInitMemory -> DVDInit) that runs before a mobile host's framework
  exists, and exited when it found nothing -- so no host importer could ever be ordered ahead of
  it. Observed going in: the installed Simulator build launched with no STRIKERS_DATA prints the
  refusal and exits before UIKit exists, with no message box (doc 36's N5 design-of-record section
  holds that transcript). A second defect surfaced while measuring the first: any exit path taken
  before the renderer exists died by signal instead of by status.
Hypothesis: (1) a disc the port cannot use should be *recorded* rather than fatal, because a
  static initialiser has no way to present anything, and the entry point -- after the framework,
  before any game code reads the disc -- is the only place a host importer can run; (2) the
  SIGSEGV was GLInventory's destructor walking containers Create() had never built, which the
  m_bCreated flag already tracks.
Change: fork ffeff97 guards ~GLInventory() with m_bCreated (Create() and Delete() already keep
  that flag, so no new state). Fork c28a6d7 adds include/port/gamedata.h (PortGameDataReady,
  ErrorTitle, ErrorMessage, Resolve), turns dvd.c's three fatal sites into a recorded refusal,
  makes open_image/index_image_fst return status, adds dvd_forget() (frees the entry table,
  closes the image, clears the disc-id/region/game-code/maker-code caches) so a re-resolve is not
  honest merely by being called, and adds the two weak hooks PortHostUIGameDataPath /
  PortHostUIRunGameDataImport in src/platform/hostui.c; main.cpp gains an unconditional step-0
  block before PortConfigLoad that asks the host to import and calls port_fatal with the same text
  it always used when the host declines or still cannot resolve.
Command / exit status: export-patches.sh --check-only -> 0 ('series reproduces the fork tree
  exactly (15d79868...)', digest bc19ccd92c75...); build.sh --platform simulator --configuration
  Release --no-bootstrap -> 0; build.sh --platform macos --configuration Release --no-bootstrap
  -> 0. Desktop matrix run from a scratch cwd with STRIKERS_NO_MESSAGEBOX=1 (without it the
  refusal box blocks in SDL_ShowSimpleMessageBox until dismissed, which is what the first attempt
  did): no data -> exit 1 with the unchanged refusal; valid STRIKERS_DATA + bounded capture exit
  -> exit 0 printing '[port] DVD: disc G4QE01 (USA)'; STRIKERS_BACKEND=zzz -> exit 1. The crash
  counterfactual was taken, not asserted: with GLInventory.cpp restored from ffeff97^ and
  rebuilt, the bad-backend run exits 139; restoring the file rebuilds byte-for-byte the same
  binary (5f9a1a1b93f2), and the fork is clean afterwards.
Runtime scene / duration / device-or-Simulator: desktop macOS (M2) for the exit-code matrix; the
  Simulator bundle was relinked and re-asserted but not re-run at this checkpoint. Runtime
  behaviour of the seam itself is unproven until Ballpad's own importer exists.
Evidence bundle: build/native/logs/build-simulator-n5-relink.log (platform metadata ok ->
  iossimulator), build/native/logs/build-macos-preGL.log and build-macos-postGL.log,
  build/native/patch-series.sha256, and the three scratch matrices under /tmp/ballpad-*matrix-*
  and /tmp/ballpad-*preGL-*, /tmp/ballpad-*postGL-* (transient; the numbers are recorded here)
Result: PASS for the port-side change and the defect fix. This does NOT close N4-D's Files-import
  half: the port now offers the seam, and no host implements it yet.
What this result does and does not prove: proves the port can refuse a disc without exiting, that a
  re-resolve starts from a clean slate rather than inheriting the refused disc's caches, that a
  desktop build with no host hooks behaves exactly as it did before (same text, same exit codes,
  which the N1/N3 proofs and the scenario runner's STRIKERS_DATA route depend on), and that a
  failed start now exits with the status it chose instead of dying in __cxa_finalize. Does not
  prove: that any host implements the two hooks (none does yet); that the Simulator app can import
  anything; that the seam is pulled into the app's link at all -- hypothesis 15's extension is the
  open trap, since a weak no-op in the port satisfies both symbols unless the app names them
  explicitly; or anything about audio, which is R2 and still unrun.
Next concrete action: write mobile/interface/BallpadGameData.mm -- PortHostUIGameDataPath() as
  pure C over <container>/Documents/BallpadGameData/, PortHostUIRunGameDataImport() driving the
  Files picker, validation through the port's own reader, activation as a write of 'current' only,
  and both symbols added to the app's existing whole-archive/'-Wl,-u' pull -- then prove an
  env-free install presents Ballpad's importer instead of the refusal.
```

## Checkpoint template

```text
Phase / gate: N4-D Files-import half -> N5 (Ballpad's own importer; doc 34 F01 + F02)
Date / build identity / patch digest: 2026-09-15; engine fork c28a6d7, tree
  15d79868707266c914904c5a487f62d88a44f2ea clean; patch series bc19ccd92c75 (9 patches); disc
  da80883ba456 (the recorded baseline); app binary 90f7a37767fc (simulator-release, unchanged by
  this session's harness work)
Source invariant and observed failure: a fresh install with no game data must present Ballpad's own
  importer rather than the port's refusal, a valid local raw USA image chosen through the Files
  picker must stage and activate, and an invalid image must be refused without disturbing the
  installation that was already working. The port had already stopped exiting when it could not
  resolve a disc (c28a6d7), but no host implemented the two hooks, so the app still had nothing to
  show. Separately, F02's refusal walk had failed repeatedly: the suite could not find the app's
  folder in the picker.
Hypothesis: (1) the app's own store, not a port change, is what closes this -- validation through
  the port's own reader, activation as a single write of `current`, and both host symbols pulled
  into the link explicitly, since a static-archive implementation is otherwise silently satisfied
  by the port's weak no-op (hypothesis 15); (2) F02's failure was a picker-match defect rather than
  a scroll or timing problem (hypothesis 21).
Change: `mobile/interface/BallpadGameData.{h,mm}` -- `PortHostUIGameDataPath()` as pure C over
  `<container>/Documents/BallpadGameData/` (it is called from a static initialiser, so it must not
  touch a UI framework), `PortHostUIRunGameDataImport()` driving the Files picker, staged copies in
  `import-<uuid>/<name>` named by a `current` file, and both symbols added to the app's existing
  whole-archive/`-Wl,-u` pull. `mobile/CMakeLists.txt` adds the file and
  `-framework UniformTypeIdentifiers`. `mobile/interface/BallpadHostUI.mm` routes three of the four
  vendored delegate actions there (re-import/change, folder import, removal); controller mapping
  stays log-only by decision (R1 row 7). Harness: `pickerContainer(named:timeout:)` and its
  documented `Browse` outcomes in the UI suite. The nine vendored SunPad files are untouched.
Command / exit status: build-for-testing of BallpadNativeUITests -> TEST BUILD SUCCEEDED (the cheap
  check before spending simulator time); `run-uitests.sh --run-id f02-only-r1 --only
  testRefusedImportKeepsThePreviousInstallationUsable` -> F02 PASS in 209 s;
  `run-uitests.sh --run-id f01f02-phone-r4 --device 8619020B-...` -> exit 0, 10/10 rows PASS,
  `problems: []`; `run-uitests.sh --run-id f01f02-pad-r1 --device B3799189-...` -> exit 0, 10/10
  rows PASS, `problems: []`. Exactly one Simulator was booted at a time throughout: the idle device
  was shut down before each run, and both are shut down now.
Runtime scene / duration / device-or-Simulator: real app, real touches. Phone `f01f02-phone-r4`:
  menu-order 28.3 s, settings-panel 98.2 s, render-scale-persistence 86.4 s,
  layout-move-reset-persistence 104.3 s, lifecycle-surface 41.7 s, F01 11.3 s, F02 200.7 s. iPad
  `f01f02-pad-r1`: menu-order 9.6 s, settings-panel 32.7 s, render-scale-persistence 21.0 s,
  layout-move-reset-persistence 38.9 s, lifecycle-surface 20.0 s, F01 89.1 s, F02 87.8 s.
Evidence bundle: `build/proofs/native-strikers/uitest-phone-f01f02-phone-r4/` and
  `build/proofs/native-strikers/uitest-pad-f01f02-pad-r1/` -- `result.json` (rows + problems),
  `uitest.log`, `preflight.log` (device, app binary hash, fixtures and their fixtures' hashes),
  `store-inventory.txt`, and the xcresult with the picker/menu hierarchy attachments. F02's
  `S.f01f02.store-bytes` row checks the staged file against the fixture the picker offered, and
  confirms the three chosen files were left unchanged.
Result: PASS for doc 34's F01 and F02 on phone and iPad, and for the N4-D Files-import half.
  N4 remains open only on F04's per-control game-consumption row and F06's rotated relayout.
What this result does and does not prove: proves the app presents its own importer with no data at
  all, that an image chosen through the real Files picker is staged byte-identically and becomes
  the active install, that a truncated or wrong-game image is refused with the previous install
  still usable and the source files unchanged, and that the vendored interface's rows and handlers
  still behave on both form factors. Does not prove: that the store survives a reinstall or a
  device restore (F09/F10's saves work is unrun), that audio is correct or even present (R2/F09 is
  unrun -- no run so far contains an audio-device open, a MusyX init or an underrun line), that any
  Setting changes the runtime rather than only persisting (R1 row 5), or anything about
  performance, memory or endurance (N6).
Next concrete action: R1 rows 5, 7 and 9-15. Row 5 first: prove each touch setting reaches the
  runtime -- render scale through `PortSetRenderScale`, the FPS row through the port's own
  `PortSetFrameLimit` (not a speed change: the port's logic advances once per retrace, so the row
  must be named as the port's limiter), and the six touch settings by reading back what the overlay
  the port reads. Aspect needs a small port-side setter first, because `src/platform/aspect.c`
  resolves once behind `STRIKERS_ASPECT` and caches, and that changes the patch digest. Then row 12
  (remove the emulated-CPU row, which doc 33 forbids shipping), rows 9-11 and 13-15, F04's
  per-control touch drive, F06's rotated relayout, and R2's audio measurement.
```

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

Update the current-state section and next action at every meaningful checkpoint so another agent
can resume without replaying completed work. A summary is not a substitute for the evidence
bundle, and missing temporary research logs do not prevent a fresh verified baseline.
