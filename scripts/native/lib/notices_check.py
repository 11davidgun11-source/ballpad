#!/usr/bin/env python3
"""Verify Ballpad's dependency inventory against the notices it actually ships.

This checks the integrity of the attribution data, not legal ownership: it
answers "does every component the app ships have the notice we say it has, and
do the tracked files, the manifest and the built bundle agree?".

Reported lines are prefixed with ok:, FAIL: or --: so the caller can colourize
them. The exit status is 0 only when nothing failed.
"""

import argparse
import hashlib
import json
import os
import sys

SCHEMA = "ballpad-native-dependency-manifest/1"
SHIPPED_VALUES = ("yes", "no", "planned")

# Doc 35 requires these three credits by name: the native port, the community
# decompilation it builds on, and the platform/graphics layer.
REQUIRED_CREDIT_URLS = (
    "https://github.com/new-coke/strikers",
    "https://github.com/yannicksuter/smstrikers-decomp",
    "https://github.com/encounter/aurora",
)

# File-name fragments of game-derived branding that doc 35 requires the new
# application bundle to exclude. Matched case-insensitively against basenames.
GAME_DERIVED_MARKERS = (
    "mc_icon",
    "strikers.icns",
    "strikers.ico",
    "strikers.rc",
    "settings.icns",
    "settings.ico",
    "settings.png",
    "settings.rc",
)

RESULT = {"ok": [], "FAIL": [], "skip": []}


def ok(msg):
    RESULT["ok"].append(msg)


def fail(msg):
    RESULT["FAIL"].append(msg)


def skip(msg):
    RESULT["skip"].append(msg)


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def walk_files(root):
    """Relative paths of every regular file under root, sorted."""
    found = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            full = os.path.join(dirpath, name)
            if os.path.islink(full) and not os.path.exists(full):
                continue
            found.append(os.path.relpath(full, root))
    found.sort()
    return found


def load_manifest(path):
    try:
        with open(path) as handle:
            return json.load(handle)
    except (IOError, ValueError) as exc:
        fail("manifest {0} is not readable JSON: {1}".format(path, exc))
        return None


def component_id(component):
    return component.get("id", "?")


def check_inventory(repo_root, manifest_path, final):
    manifest = load_manifest(manifest_path)
    if manifest is None:
        return None

    if manifest.get("schema") != SCHEMA:
        fail("manifest schema is {0}, expected {1}".format(manifest.get("schema"), SCHEMA))
    else:
        ok("manifest schema is {0}".format(SCHEMA))

    components = manifest.get("components")
    if not isinstance(components, list) or not components:
        fail("manifest has no components array")
        return manifest

    ids = [component_id(component) for component in components]
    duplicates = sorted(set(cid for cid in ids if ids.count(cid) > 1))
    if duplicates:
        fail("manifest component ids are not unique: {0}".format(", ".join(duplicates)))
    else:
        ok("manifest lists {0} components with unique ids".format(len(ids)))

    notice_dir = os.path.join(repo_root, "notices")
    if not os.path.isdir(notice_dir):
        fail("no notices directory at {0}".format(notice_dir))
        return manifest

    on_disk = set(walk_files(notice_dir))
    claimed = set()
    gaps = []

    for component in components:
        cid = component_id(component)
        shipped = component.get("shipped")
        notices = component.get("notices")
        gap = component.get("notice_gap")

        if shipped not in SHIPPED_VALUES:
            fail("component {0} has shipped={1!r}, expected one of {2}".format(
                cid, shipped, ", ".join(SHIPPED_VALUES)))
            continue

        if not isinstance(notices, list):
            fail("component {0} has no notices array".format(cid))
            continue

        for entry in notices:
            relative = entry.replace("notices/", "", 1) if entry.startswith("notices/") else entry
            relative = os.path.normpath(relative)
            if relative not in on_disk:
                fail("component {0} claims notice {1}, which is not in the notices directory".format(cid, entry))
            else:
                claimed.add(relative)

        if shipped == "no":
            if notices:
                fail("component {0} is not shipped but still claims notices".format(cid))
            else:
                ok("not-shipped component {0} claims no notices".format(cid))
            continue

        if gap:
            gaps.append((cid, gap))
            skip("component {0} ({1}) records a notice gap: {2}".format(cid, shipped, gap))
        elif not notices:
            fail("shipped component {0} ({1}) has no notice".format(cid, shipped))
        else:
            ok("shipped component {0} ({1}) claims {2} notice file(s)".format(cid, shipped, len(notices)))

    orphans = sorted(on_disk - claimed - set(["README.md"]))
    if orphans:
        fail("notices directory holds files no component claims: {0}".format(", ".join(orphans)))
    else:
        ok("every notice file is claimed by a manifest component")

    if final:
        for cid, gap in gaps:
            fail("final inventory still has a notice gap for {0}: {1}".format(cid, gap))
        planned = [component_id(component) for component in components
                   if component.get("shipped") == "planned"]
        if planned:
            fail("final inventory still marks components as planned: {0}".format(", ".join(planned)))
        else:
            ok("no component is left in the planned state")

    return manifest


def check_documents(repo_root, manifest):
    attribution = os.path.join(repo_root, "ATTRIBUTION.md")
    notices_md = os.path.join(repo_root, "THIRD_PARTY_NOTICES.md")
    index = os.path.join(repo_root, "notices", "README.md")

    for label, path in (("ATTRIBUTION.md", attribution),
                        ("THIRD_PARTY_NOTICES.md", notices_md),
                        ("notices/README.md", index)):
        if os.path.isfile(path):
            ok("{0} is present".format(label))
        else:
            fail("{0} is missing at {1}".format(label, path))

    if os.path.isfile(attribution):
        with open(attribution) as handle:
            text = handle.read()
        for url in REQUIRED_CREDIT_URLS:
            if url in text:
                ok("ATTRIBUTION.md credits {0}".format(url))
            else:
                fail("ATTRIBUTION.md does not credit {0}".format(url))

    if os.path.isfile(notices_md) and manifest:
        with open(notices_md) as handle:
            text = handle.read()
        missing = [component_id(component) for component in manifest.get("components", [])
                   if component_id(component) not in text]
        if missing:
            fail("THIRD_PARTY_NOTICES.md does not mention: {0}".format(", ".join(missing)))
        else:
            ok("THIRD_PARTY_NOTICES.md mentions every manifest component")


def parse_resource_list(path):
    """Rows of a generated notices/resources.txt: (sha256, size, relative path)."""
    rows = []
    with open(path) as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 3:
                continue
            try:
                size = int(parts[1])
            except ValueError:
                continue
            rows.append((parts[0], size, parts[2]))
    return rows


def check_bundle(bundle, repo_root, manifest, required):
    if not bundle:
        if required:
            fail("--require-bundle was given but no bundle was located")
        else:
            skip("no bundle supplied; run with --platform to check the shipped app")
        return
    if not os.path.isdir(bundle):
        if required:
            fail("expected bundle at {0} does not exist".format(bundle))
        else:
            skip("no bundle at {0} yet".format(bundle))
        return

    ok("bundle present at {0}".format(bundle))

    bundled_notices = os.path.join(bundle, "notices")
    if not os.path.isdir(bundled_notices):
        fail("bundle has no notices directory at {0}".format(bundled_notices))
    else:
        present = set(walk_files(bundled_notices))
        expected = set()
        for component in (manifest or {}).get("components", []):
            for entry in component.get("notices", []) or []:
                relative = entry.replace("notices/", "", 1)
                expected.add(os.path.normpath(relative))
        missing = sorted(expected - present)
        if missing:
            fail("bundle notices are missing: {0}".format(", ".join(missing)))
        else:
            ok("bundle ships all {0} claimed notice file(s)".format(len(expected)))

        mismatched = []
        for relative in sorted(expected & present):
            tracked = os.path.join(repo_root, "notices", relative)
            shipped = os.path.join(bundled_notices, relative)
            if not os.path.isfile(tracked) or sha256_of(tracked) != sha256_of(shipped):
                mismatched.append(relative)
        if mismatched:
            fail("bundle notice text differs from the tracked copy: {0}".format(", ".join(mismatched)))
        else:
            ok("bundle notice text is byte-identical to the tracked inventory")

        list_path = os.path.join(bundled_notices, "resources.txt")
        if not os.path.isfile(list_path):
            fail("bundle notices do not include resources.txt, so the generated resource list is unverified")
        else:
            rows = parse_resource_list(list_path)
            listed = set(row[2] for row in rows)
            unclaimed = sorted(expected - listed)
            unlisted = sorted(present - listed - set(["manifest.json", "resources.txt"]))
            absent = sorted(relative for relative in listed if relative not in present)
            if unclaimed:
                fail("resources.txt does not list claimed notices: {0}".format(", ".join(unclaimed)))
            if unlisted:
                fail("bundle notices hold files the resource list does not list: {0}".format(", ".join(unlisted)))
            if absent:
                fail("resources.txt lists files the bundle does not carry: {0}".format(", ".join(absent)))
            bad = []
            for digest, _size, relative in rows:
                tracked = os.path.join(repo_root, "notices", relative)
                if not os.path.isfile(tracked) or sha256_of(tracked) != digest:
                    bad.append(relative)
            if bad:
                fail("resources.txt hashes disagree with the tracked notices: {0}".format(", ".join(bad)))
            if not (unclaimed or unlisted or absent or bad):
                ok("resources.txt accounts for every shipped notice with a matching hash")

        if "manifest.json" in present:
            tracked_manifest = os.path.join(repo_root, "docs", "native-strikers-dependency-manifest.json")
            if sha256_of(os.path.join(bundled_notices, "manifest.json")) == sha256_of(tracked_manifest):
                ok("bundle manifest is the tracked dependency manifest")
            else:
                fail("bundle manifest.json differs from docs/native-strikers-dependency-manifest.json")
        else:
            fail("bundle notices do not include manifest.json, so About/Credits cannot enumerate them")

    offenders = []
    for relative in walk_files(bundle):
        base = os.path.basename(relative).lower()
        for marker in GAME_DERIVED_MARKERS:
            if marker in base:
                offenders.append(relative)
                break
    if offenders:
        fail("bundle contains game-derived branding: {0}".format(", ".join(sorted(offenders))))
    else:
        ok("bundle contains no game-derived application branding")


def main():
    parser = argparse.ArgumentParser(description="Check the notices inventory and the shipped bundle.")
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--bundle", default="")
    parser.add_argument("--require-bundle", action="store_true")
    parser.add_argument("--final", action="store_true",
                        help="treat recorded notice gaps and planned components as failures")
    parser.add_argument("--inventory-only", action="store_true")
    args = parser.parse_args()

    manifest = check_inventory(args.repo_root, args.manifest, args.final)
    check_documents(args.repo_root, manifest)
    if not args.inventory_only:
        check_bundle(args.bundle, args.repo_root, manifest, args.require_bundle)

    for message in RESULT["ok"]:
        sys.stdout.write("   ok " + message + "\n")
    for message in RESULT["skip"]:
        sys.stdout.write("   -- " + message + "\n")
    for message in RESULT["FAIL"]:
        sys.stderr.write(" FAIL " + message + "\n")

    if RESULT["FAIL"]:
        sys.stderr.write("notices: {0} check(s) failed\n".format(len(RESULT["FAIL"])))
        return 1
    sys.stdout.write("notices: all checks passed\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
