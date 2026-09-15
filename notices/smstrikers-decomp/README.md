# Community decompilation material in the native port

`new-coke/strikers` is a native port that builds on the Super Mario Strikers community
decompilation led by Yannick Suter:

- Port: https://github.com/new-coke/strikers (pinned at `22649cb12c112454a34217429296c95bb181af8a`, v1.1.1)
- Decompilation: https://github.com/yannicksuter/smstrikers-decomp

The reconstructed game sources, the vendored ODE physics copy and the vendored MusyX
audio middleware all originate in that decompilation effort. They are present in the
pinned engine tree that this project builds, not fetched separately at Ballpad build time.

## Rights status

This material is an unofficial source reconstruction, not an official source release.
No upstream license grants distribution rights for the reconstructed game code, and the
reconstruction's own rights status is unresolved. Nothing in this directory, in
`ATTRIBUTION.md`, or in the port author's CC0 offer should be read as relicensing it, as
evidence that a licensor holds every underlying right, or as clearing it for
redistribution. Ballpad claims no rights in it and does not present it as newly authored
Ballpad work; upstream authorship is preserved in Git and in the exported patch series.

## Files

- `LICENSE-GPL-2.0.txt`, `LICENSE-LGPL-2.1.txt` - the license texts carried in the
  pinned engine tree alongside the reconstructed sources, reproduced verbatim here so
  they travel with the app. Their presence records what upstream shipped; it does not
  establish that the upstream licensors hold all rights in the reconstructed material.

The vendored MusyX and ODE copies keep their own notices, recorded separately under
`notices/musyx/` and `notices/ode/`.

