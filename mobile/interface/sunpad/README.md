# SunPad's iOS interface, vendored

This directory is a byte-for-byte copy of SunPad's iOS touch interface. It is here so that
Ballpad's GameCube controls and its three-dot primary-action menu are *SunPad's* geometry and
behaviour rather than a retyped approximation of them (doc 36 requirement R1).

Source: [chrissotraidis/sunpad](https://github.com/chrissotraidis/sunpad), revision `e43f0ea6b797e5110787171957c9dc3c6213269c`
(clean working tree at copy time).

| File | Copied from | sha256 |
|---|---|---|
| `SunPadGameOverlay.h` | `apple/ios/SunPadGameOverlay.h` | `161200ac2815d18366fff3b726e7aec1e8c9b0839c4266e211c5bebbce1fbe54` |
| `SunPadGameOverlay.mm` | `apple/ios/SunPadGameOverlay.mm` | `4d7cd4192e846430c2bed0737956b859cf03f52424617fa5b7bd470d5a6bfa4b` |
| `SunPadInputState.h` | `apple/shared/SunPadInputState.h` | `67ecd1014f32e4e81573baeb5819b438eb5ebaf4fd1dc3d79169da9a6f71e4d9` |
| `SunPadInputMixer.h` | `apple/shared/SunPadInputMixer.h` | `647bdec3a60e1ff8b5a95ba6f7034ff80dae84bcaea9c8514d23f80ade19cd4c` |
| `SunPadInputMixer.mm` | `apple/shared/SunPadInputMixer.mm` | `6ee9d671db17961676f71d0da3a80c4b9ea2d9de2aecf11c2041bc593faaa33b` |
| `SunPadControllerSlots.h` | `apple/ios/SunPadControllerSlots.h` | `35384bc083a5a0499d48f8ab9d7e4a7abd7ec21437b5d13b66f7528a2900c164` |
| `SunPadControllerMapping.h` | `apple/shared/SunPadControllerMapping.h` | `267222d1d8eda050deedb5d986401a57f2a7e6d9f010c84e83caa51e11582f1c` |
| `SunPadControllerMapping.mm` | `apple/shared/SunPadControllerMapping.mm` | `510d129b21ba6aeb1a4ae4631db8063a52229e5b1666ae3323ae9fa8a1753060` |
| `SunPadSettings.h` | `apple/shared/SunPadSettings.h` | `63e46d5eade0516fd16f1a852dfd4cf67a65c6ab10e08bf9f5794957e4700bd7` |
| `SunPadSettings.mm` | `apple/shared/SunPadSettings.mm` | `d2cbfc15605ccf9b44303a02cef0f36a877deedd2ddba8bad84a03a4625f9c40` |
| `SunPadDiagnostics.h` | `apple/shared/SunPadDiagnostics.h` | `d7b899d43cafd5ee4a77b3c113339676bacdd3e712719575f802459e285800b1` |
| `SunPadDiagnostics.mm` | `apple/shared/SunPadDiagnostics.mm` | `89560621c658387de44711c2d69eb89aca3eceeb8fec94ff8e26ea7424cb6be3` |

## Rules for this directory

- Do not edit these files. They are the fidelity reference; an edit here makes "exactly as they
  are" unverifiable. Ballpad's changes belong in the adaptation layer one directory up.
- When SunPad moves, re-copy and update the table above together, so the diff between the two
  projects is always visible as a diff rather than as an undocumented local edit.
- These files are GPL-3.0, from the operator's own sibling project. They are not relicensed by
  being copied here, and they carry their own header notices unchanged.

SunPad's overlay is self-contained on purpose here: it references only `SunPadSettings`,
`SunPadInputMixer`, `SunPadDiagnostics` and `SunPadInputState.h`, plus UIKit, GameController and
QuartzCore. It has no Sunshine or Dolphin dependency, which is what makes it adoptable on
Ballpad's runtime at all.
