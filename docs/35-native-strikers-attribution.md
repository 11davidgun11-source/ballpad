# Native Strikers attribution and provenance

## Required approach

Credit the native port explicitly and preserve every applicable upstream notice. The project combines material with different rights statuses; no root license should imply that reconstructed game code or third-party dependencies have been relicensed by Ballpad. This is an engineering provenance specification, not legal clearance.

Sources of truth: the reviewed [upstream README](https://github.com/new-coke/strikers/blob/22649cb12c112454a34217429296c95bb181af8a/README.md), each dependency's actual license files, and the immutable links in the [research report](research/strikers-ios-feasibility.md). Refresh relevant authoritative legal/distribution documentation if preparing a future public release. Do not infer rights from the existence of upstream binary releases.

## README and About credit text

Use this text, adapting the app name only if needed:

> Ballpad's native iOS/iPadOS engine is based on [new-coke/strikers](https://github.com/new-coke/strikers), a native desktop port of Super Mario Strikers. The native port builds on the community decompilation by [Yannick Suter and contributors](https://github.com/yannicksuter/smstrikers-decomp), and uses [Aurora](https://github.com/encounter/aurora) and its contributors' work for platform and graphics support. Ballpad adds the iOS/iPadOS application integration, touch interface, and mobile build/test work. See the bundled third-party notices for dependency licenses and provenance.
>
> This is an unofficial project, unaffiliated with and not endorsed by Nintendo or Next Level Games. Supply your own lawfully obtained game data. The project grants no rights to redistribute game assets or disc images. Attribution does not grant rights to reconstructed game code or other third-party material.

Identify the exact upstream revision separately. Preserve upstream authorship in Git and patch metadata; do not present inherited code as newly authored Ballpad code. Do not add invented contributor names or copyright dates. Verify the credited source URLs against the dependency manifest.

## Required tracked deliverables

- `ATTRIBUTION.md`: prominent credits, engine/decomp/Aurora relationships, local contribution boundary, pinned revisions, and rights-status limitations.
- `THIRD_PARTY_NOTICES.md` plus verbatim license texts in a notices directory: copied from the actual pinned sources, available offline in the app bundle.
- Machine-readable dependency/provenance inventory: component, upstream URL, revision/archive hash, license file, local modifications, built targets and whether shipped. Inventory the native engine separately from Aurora, Dawn, SDL, MusyX, ODE and FFmpeg, and include all actual transitive distributed dependencies.
- A build-generated or validated resource list so About/Credits ships the same notices described in the inventory. Verify the built bundle, not only source files.
- A local release-readiness note separating completed attribution, unresolved rights questions, physical-device status and non-public development scope.

The port author's original material is offered under CC0 only within their rights; carry this qualification. Aurora's MIT notice, MusyX's preserved notice, ODE's BSD-style notice and other actual dependency notices retain their terms. A notice attached to reconstructed material does not prove the licensor owns every underlying right. Do not resolve ambiguity by assigning MIT/CC0 to the entire engine.

FFmpeg: record the exact configure flags and enabled libraries/decoders; include applicable notices and source/relinking requirements for the actual linkage/configuration. Do not assume that a THP-only static library has no obligations or that including a license file alone completes compliance. Track unresolved distribution obligations explicitly. Avoid unnecessary GPL/nonfree configuration, but preserve truth if any is actually used.

## Assets and brand audit

Inspect `smstrikers-port/assets/icon/`, including `MC_Icon.tpl`, derived PNG/ICO/ICNS files, and `src/platform/mc_icon.h`, along with every application resource and packaging script. Follow references and generated resources so embedded copies are not missed. Retain provenance records, but exclude game-derived artwork from the new application bundle; replace application branding with original simple artwork. Do not rewrite upstream Git history to pretend those files never existed.

Game assets needed during play must be loaded from the user's imported data. If a memory-card UI needs original artwork, load it from that imported data rather than embedding an upstream ripped copy. Verify that asset cleanup does not damage save format behavior.

Before staging changes, scan for original game images, DOLs, extracted files, cards, screenshots, videos, crash dumps and local paths/secrets that should remain ignored. Public source publication is a separate decision: keeping assets out of the bundle does not make every reconstructed source file cleared for redistribution.

## Acceptance

Credit wording is visible in README and About; exact engine provenance is inspectable; full notices are bundled offline; license inventory matches actual linked components; asset-derived application branding is excluded; local changes are accurately attributed. `verify-notices.sh` must fail when a shipped component lacks a required notice or the manifest/resource list is inconsistent. A passing script checks inventory integrity, not legal ownership.
