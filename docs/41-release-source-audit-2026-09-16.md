# Release source and attribution audit — 2026-09-16

BallPad is an iOS/iPadOS port of **new-coke/strikers**, with upstream attribution
retained prominently in the README and the offline app credits. This audit
records source provenance and distribution gaps; it does not claim clearance of
reconstructed code or immunity from criticism.

## Source identity

- Maintained engine: `https://github.com/chrissotraidis/strikers`.
- Live GitHub API confirms this is a public registered fork of `new-coke/strikers`.
  The `ballpad-ios` branch resolves to the pinned commit, and the commit API returns
  that exact SHA. The upstream-facing `main` branch is separate.
- Pinned engine commit: `37c0ad9a1d2b4fc5627943d737b9db54047f1f0e`.
- Upstream: `https://github.com/new-coke/strikers`, v1.1.1,
  `22649cb12c112454a34217429296c95bb181af8a`.
- The upstream base is an ancestor of the maintained revision. Existing upstream
  commits remain intact; mobile adaptations and bounded movie/scene diagnostics
  are subsequent commits. Normal source setup now selects the maintained commit
  directly, without patch application.
- BallPad remains the Apple application repository; the Strikers fork is the
  engine repository. Source archives need both exact revisions and the relevant
  dependency source/build material.

## Documentation changes

README, attribution, and manifest now describe the maintained-fork workflow and
retain the upstream base separately. Credit roles include new-coke's native port,
Yannick Suter and the decompilation contributors, Aurora/Dawn, SDL, FFmpeg, SunPad,
and their dependencies. Existing component license limitations are retained.

Both requested Discord badges are at the top of the README. The public Discord
API verified `UwhfwXx4C` points to Kahris and expires on 2026-10-16 at 11:49:34 UTC.
The earlier `xwHfUD2bxW` invite is retained. Expiring invitation links need renewal
if they are to remain a lasting project entry point.

The owner reports gameplay working on iOS and iPadOS. The README distinguishes
that report from full-game/performance acceptance, and retains reported intro
movie and stadium rendering defects plus unverified two-controller play.

## Candidate-specific checks

The fork's live parent, `ballpad-ios` branch, and accessible pinned commit were
verified through GitHub API. Final inventory-only notice checks passed for all
11 components; local document links and whitespace checks passed. The publication
task must verify the final app source commit, final notice bundle, clean source build checks,
and uploaded IPA/source/relink hashes. Historic patch replay success does not
replace those checks after changing the build workflow. Artifact results belong
to the exact release record, not to this source documentation edit.

## Distribution work still requiring evidence

- SunPad GPL-3.0 corresponding source and build information for the distributed
  combined application, with clear licensing scope for BallPad-authored material.
- FFmpeg LGPL source/configuration and matching relink inputs, with fresh relink
  validation for the candidate executable and accessible release delivery.
- Applicable third-party notices and source obligations for the actual linked set.
- Exact public source and artifact identity, usable issue/report links, and
  exclusion of private game data, saves, runtime traces, and signing material.
- Underlying rights in reconstructed game code, MusyX, and game-specific ODE
  changes remain unresolved by technical checks or attribution.

No public release or push was performed by this documentation subtask.

## Original-code license decision

The owner approved GPL-3.0-only for BallPad original code. `LICENSE` contains the
license text and `LICENSE-SCOPE.md` excludes inherited material from that grant.
The fresh maintained-source clone/configuration/probe build passed. Portable
FFmpeg relinking passed after relocation; source/archive hashes are recorded in
the final local artifact directory.

## Final pre-package validation

The native patch files were removed from the active tree; history remains in Git.
`verify-clean --scope source` and the fresh-clone probe build passed. Device and
Simulator builds passed, as did the two focused credits/report/FPS UI tests under
maintained-source provenance. Final device notice verification covers 12 inventory
components, including the approved BallPad original-code license.

A worktree and Git-object path scan found no tracked game-image/save/signing files.
This is a focused publication check, not a guarantee that criticism or undiscovered
issues are impossible. The owner controls changing the app repository’s visibility.
