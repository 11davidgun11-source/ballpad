# BallPad

<p align="center">
  <strong>Super Mario Strikers on iPhone and iPad, running on a native engine.</strong><br>
  GameCube touch controls, physical controller support, and a local importer for game data you supply.
</p>

<p align="center">
  <img alt="iOS and iPadOS 17 or later" src="https://img.shields.io/badge/iOS%20%2F%20iPadOS-17%2B-0A84FF?logo=apple">
  <img alt="Renderer: Metal" src="https://img.shields.io/badge/renderer-Metal-5E5CE6">
  <img alt="Engine: new-coke/strikers v1.1.1" src="https://img.shields.io/badge/engine-new--coke%2Fstrikers%20v1.1.1-30D158">
  <img alt="Game data not included" src="https://img.shields.io/badge/game%20data-not%20included-FF453A">
</p>

BallPad is a native iPhone and iPad app built around the
[new-coke/strikers](https://github.com/new-coke/strikers) desktop port of Super Mario
Strikers. That port sits on the community
[decompilation](https://github.com/yannicksuter/smstrikers-decomp) by Yannick Suter and
contributors, and on [Aurora](https://github.com/encounter/aurora) for platform and
graphics work. The game's original PowerPC code runs as natively compiled code — there is
no emulator and no runtime JIT — and Metal presents it full-screen.

BallPad ships no game data. You import your own disc image once through the iOS Files
picker, and BallPad keeps that image, and your memory card, inside its own sandbox.

This repository holds BallPad's own work: the iOS application shell, the touch interface
adapter, the build and test tooling, and the engine patch series. It does not contain
Super Mario Strikers, a disc image, extracted Nintendo assets, save files, or recompiled
game code.

## Status

| | |
| --- | --- |
| Simulator | The touch-interface acceptance suite passes 28/28 rows on both the iPhone and the iPad Simulator, on one app binary |
| Physical device | **Not validated.** The device build compiles and is correctly linked, but no hardware has run it |
| Public distribution | **Not decided.** No binary is published, no IPA is audited, and open rights questions remain — see [release readiness](docs/native-strikers-release-readiness.md) |
| Game data | Never bundled; supplied by you at first launch |

This is a development build, not a finished release. Moving-match performance, audio
lifecycle on hardware, save stress and oldest-OS support still need real-device
validation. The candid engineering record, including what is proven and what is not, is
[docs/36, the execution ledger](docs/36-native-strikers-progress.md).

## What works today

- **The whole game, start to finish**, in the Simulator: the front end, a live match that
  scores and presents its own replay, and the memory-card screens.
- **GameCube controls on the touchscreen**: movement stick, C-stick, D-pad, A/B/X/Y/Z,
  L/R shoulders and Start, each movable and individually resizable, with global size and
  opacity.
- **Physical controllers** through GameController, merged with touch input so both work at
  once, with an option to hide the on-screen controls while a controller is connected.
- **A three-dot menu** over the game for display options (render scale, aspect ratio, FPS),
  control settings, game data and memory-card actions, and the diagnostic log.
- **Saves** on a sandboxed Slot A memory card, with Files import and share-sheet export.

## Requirements

- An Apple Silicon Mac with Xcode 26.x and its command-line tools
- CMake, Git, Python 3.10+, and ripgrep
- Your own lawfully obtained Super Mario Strikers USA revision 0 image (`G4QE01`)

## Build and run

One-time setup: verify the toolchain, clone the pinned engine into the ignored working
fork, apply BallPad's patch series, and stage the pinned dependencies.

```sh
scripts/native/bootstrap.sh --platform simulator
```

Build the Simulator app:

```sh
scripts/native/build.sh --platform simulator
```

Install and launch it on a booted Simulator:

```sh
xcrun simctl install booted build/native/simulator-release/port/BallpadStrikers.app
xcrun simctl launch booted com.ballpad.strikers
```

Build the device app the same way (`--platform device`). That bundle is left unsigned,
so signing it for your own hardware is yours to arrange.

## First launch

BallPad never downloads or bundles game data.

1. Launch BallPad. With no game data present it opens **Add your game**.
2. Choose **Choose ISO or GCM** and pick your raw `G4QE01` revision 0 image — or put that
   image into BallPad's own folder in the Files app and choose **Import from BallPad
   Folder**.
3. Leave BallPad open while the image is copied in and checked.
4. Choose **Start the Game** once it reports the data is ready.

The wrong game code, the wrong disc revision, a bad header or an unexpected size is
refused, and whatever game data is already in place keeps working. The image and the
memory card live in `Documents/BallpadGameData/` inside the app sandbox; use
**Game Data** from the menu to replace the image later.

For scripted runs, the scenario driver can hand the engine an image directly rather than
importing one: `SIMCTL_CHILD_STRIKERS_DATA=/path/to/G4QE01.iso`.

## Controls

The overlay is SunPad's, so a BallPad layout is the layout SunPad already shipped.

- **Left:** movement stick, D-pad, and L.
- **Right:** C-stick, A/B/X/Y, Z, R, and Start.
- **Shoulders:** one touch produces the GameCube analog value and the digital click
  together, so no swipe or edge hit is needed.
- **Customize:** **Touch Control Settings** in the menu moves and resizes individual
  controls and sets the global size and opacity. Positions are stored per device class, so
  the phone and the pad keep their own layouts.
- **Handoff:** touch and controller input are merged with rising-edge latching, the
  strongest stick axis wins, and the greatest trigger pressure wins, which keeps fast taps
  and mixed-input sessions stable across the input and render threads.

## Supported game data

| Game ID | Region | Revision | Raw size |
| --- | --- | ---: | ---: |
| `G4QE01` | USA | 0 | 1,459,978,240 bytes |

Raw ISO and GCM images are recognized. Compressed images are not supported.

## Project layout

| Path | Purpose |
| --- | --- |
| [`mobile/`](mobile/) | The iOS app: engine bridge, interface adapter, importer, and credit screens |
| [`mobile/interface/sunpad/`](mobile/interface/sunpad/) | SunPad's iOS overlay, vendored byte-for-byte; its README records provenance, hashes and license |
| [`patches/native-strikers/`](patches/native-strikers/) | BallPad's engine changes, exported as a reapplicable patch series |
| [`scripts/native/`](scripts/native/) | Bootstrap, build, test, scenario, notice and clean-reproduction tooling |
| [`tests/native/`](tests/native/) | Driven scenarios and the XCUITest acceptance bundle |
| [`notices/`](notices/), [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) | Third-party license material, also shipped inside the app |
| [`docs/33`](docs/33-native-strikers-implementation.md)-[`36`](docs/36-native-strikers-progress.md) | Runbook, acceptance specification, attribution rules, and the execution ledger |
| `app/`, `host/` | The superseded static-recompilation implementation, kept for history |

## Tests and evidence

Every run writes a proof bundle under `build/proofs/native-strikers/<run-id>/`, and a row
that did not run fails the run rather than going missing.

| Command | What it answers |
| --- | --- |
| `scripts/native/test.sh --suite unit` | The engine and the port's own tests on macOS |
| `scripts/native/test.sh --suite smoke --device <UDID>` | The app presents real frames on Simulator Metal |
| `scripts/native/test.sh --suite acceptance --device <UDID>` | The functional matrix on a Simulator |
| `scripts/native/run-uitests.sh --run-id <id> --device <UDID> [--form-factor pad]` | The touch-interface suite, by real touches on the app's own surface |
| `scripts/native/run-scenario.sh --scenario <name> --run-id <id> --device <UDID>` | One driven scenario, with its provenance recorded |
| `scripts/native/verify-notices.sh --final --require-bundle` | The notices in the built bundle match the inventory |
| `scripts/native/verify-clean.sh --scope all` | The tracked patch series reproduces the engine from the pin, with nothing borrowed from the ignored working trees |
| `scripts/native/export-patches.sh` | Exports working-fork changes into the tracked patch series |

`build/`, `work/`, `ref/` and `.local-assets/` are ignored and must never be committed:
they hold build products, the working engine fork, and your disc image.

## Attribution and legal

BallPad's native iOS/iPadOS engine is based on
[new-coke/strikers](https://github.com/new-coke/strikers), a native desktop port of Super
Mario Strikers. The native port builds on the community decompilation by
[Yannick Suter and contributors](https://github.com/yannicksuter/smstrikers-decomp), and
uses [Aurora](https://github.com/encounter/aurora) and its contributors' work for platform
and graphics support. BallPad adds the iOS/iPadOS application integration, touch
interface, and mobile build/test work. See the bundled third-party notices for dependency
licenses and provenance.

This is an unofficial project, unaffiliated with and not endorsed by Nintendo or Next
Level Games. Supply your own lawfully obtained game data. The project grants no rights to
redistribute game assets or disc images. Attribution does not grant rights to
reconstructed game code or other third-party material.

Two qualifications matter before anything here is distributed as a binary:

- **The touch interface is GPL-3.0.** `mobile/interface/sunpad/` is a byte-for-byte copy of
  the operator's own sibling project, SunPad, and is not relicensed by being copied here.
  It is not yet entered in the notice inventory, which is one of the open items in the
  [release-readiness note](docs/native-strikers-release-readiness.md).
- **The engine's reconstructed game code** carries no upstream grant of redistribution
  rights. Partial attribution is recorded honestly rather than resolved:
  [`ATTRIBUTION.md`](ATTRIBUTION.md) lists every component with its actual license status
  and pins each upstream revision, and
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) is the same inventory the app shows in
  **About & Credits**.

No disc image, extracted Nintendo asset, or user save is included in this repository, and
none is ever bundled into the app.

## Documentation

| Document | What it is |
| --- | --- |
| [`docs/33-native-strikers-implementation.md`](docs/33-native-strikers-implementation.md) | The runbook: scope, phases, and the pinned upstream revision |
| [`docs/34-native-strikers-acceptance.md`](docs/34-native-strikers-acceptance.md) | The acceptance specification every evidence row is judged against |
| [`docs/35-native-strikers-attribution.md`](docs/35-native-strikers-attribution.md) | The attribution and provenance rules this repository follows |
| [`docs/36-native-strikers-progress.md`](docs/36-native-strikers-progress.md) | The execution ledger: current state, hypotheses, and checkpoints |
| [`docs/native-strikers-release-readiness.md`](docs/native-strikers-release-readiness.md) | What is complete, what is unresolved, and what is deliberately out of scope |
| [`docs/21-sunpad-parity-audit.md`](docs/21-sunpad-parity-audit.md) | The SunPad comparison the interface work is measured against |
