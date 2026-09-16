# BallPad attribution and repository audit — 2026-09-16

Scope: current local source, upstream relationships, README presentation, and notice
inventory. This is an engineering provenance check, not rights clearance or a public
release. Hardware deployment and testing are tracked separately.

## Verified source relationships

- Live GitHub API reports `chrissotraidis/ballpad` is **private**, `fork: false`,
  with no parent/source repository, issues enabled, default branch `main`, and no
  releases. GitHub recognizes no root license. The project must not advertise itself
  as a registered GitHub fork or offer a public download that does not exist.
- `new-coke/strikers` is also not registered as a fork. Its v1.1.1 engine commit is
  `22649cb12c112454a34217429296c95bb181af8a`. The local engine has that commit as an
  ancestor, retains upstream history, and uses the upstream Git remote. BallPad
  maintains its adaptation as 18 tracked patches; no hosted maintained-engine fork
  was found or claimed.
- `scripts/native/verify-clean.sh --scope patches` passed: clean engine worktree,
  all patches replay to the same source tree, and series digest matches the recorded
  value (`f4a699e4bbe3f09d…`). This was a source replay check, not a new clean app build.
- Upstream credits identify new-coke/strikers, Yannick Suter and the community
  decompilation, and encounter/aurora. BallPad's active app uses that native source
  port. GalaxyPad's ModernGekko/RecompCore/Dolphin architecture must not be copied
  into BallPad's active-engine description.
- All 12 vendored SunPad source files match the SHA-256 values in their provenance
  README at `e43f0ea6b797e5110787171957c9dc3c6213269c`. Adaptation stays outside that
  directory. SunPad's GPL-3.0 notice is inventoried and packaged by the app build.
- `git ls-files ref .local-assets work build` returned no files. This confirms those
  current tracked paths are empty, not a forensic audit of every historical commit.

## README and attribution corrections

The README follows GalaxyPad's readable product introduction, badges, current-status
summary, expandable FAQ/build instructions, import/controls guide, diagnostics,
project map, and credits. It retains BallPad-specific game identity and commands,
and removes the unsupported whole-game-completion wording.

The community badge uses the exact URL and badge styling in GalaxyPad's live README:
`https://discord.gg/xwHfUD2bxW`. Discord's public invite endpoint returned that code
and the **Kahris** community with no expiry on this audit date.

`ATTRIBUTION.md` now names SunPad in the source graph and pins. It distinguishes the
app repository from the adapted local engine checkout and corrects the claim that
reconstructed source is untouched: the tracked patches edit Game, NL, and MSL paths
for compatibility, diagnostics, and host integration. Examples include MSL template
compatibility, `Game/main.cpp` host integration, frontend/GL guards, and `Game.cpp`
benchmark instrumentation. This does not imply ownership of the underlying source.
The patch series does not modify vendored ODE or MusyX.

The manifest now describes the port author's CC0 offer as stated in the pinned
upstream README, rather than a blanket “MIT / CC0” label, and records the reconstructed
source modifications instead of “none.” Existing SunPad inventory content is preserved.

## Verification

- Live GitHub repository metadata and release listing read through `gh api`.
- GalaxyPad's current README fetched from its GitHub API and compared directly.
- Discord invite checked through its public API; no community message sent.
- `scripts/native/verify-clean.sh --scope patches`: passed.
- Vendored SunPad recorded hashes: all 12 matched.
- `scripts/native/verify-notices.sh --inventory-only --final`: passed after edits,
  covering 11 manifest components and matching inventory/document coverage.
- README and attribution local links checked; `git diff --check` passed for changed
  documentation/manifest files.

Final device/Simulator bundle notice verification belongs to the rebuilt candidate;
this audit's inventory check alone does not verify a newly packaged binary.

## Remaining release work

1. **Public access:** repository and issue tracker are private. Public users cannot
   use the report destination until access is deliberately changed or an accessible
   tracker is provided. No visibility change was made by this audit.
2. **Release source and licensing:** GitHub recognizes no root license. The app's
   own licensing scope needs an explicit owner decision, without purporting to
   relicense inherited material. Applicable SunPad GPL corresponding source and
   FFmpeg relink/source material must accompany any distribution; local files alone
   are not a published source offer. Existing notice text is not proof of compliance.
3. **Underlying rights:** reconstructed game code and reconstructed middleware
   limitations remain as documented in `ATTRIBUTION.md` and release readiness.
   Attributing the work, excluding game assets, or registering a GitHub fork would
   not resolve those questions.
4. **Exact candidate acceptance:** hardware installation, controller/touch behavior,
   match performance, audio lifecycle, and save preservation require evidence for
   the candidate being tested. Simulator and compile results are separate.
5. **Publication artifacts:** any public candidate needs exact source/build identity,
   hashes, complete notices and required source/relink material, and checked packaging.
   No release, push, public issue, or repository-visibility change was performed here.
