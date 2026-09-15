#!/usr/bin/env python3
"""Assemble the notices resources for a built Ballpad app bundle.

This is the build side of doc 35's requirement for a build-generated resource list. It
copies the tracked notice texts into bundle/notices/, drops in the machine-readable
dependency manifest as notices/manifest.json so About/Credits can enumerate them offline,
and writes notices/resources.txt listing every file it placed, with its SHA-256. The list
is generated from what was actually copied, so it cannot claim a file the bundle does not
carry.

Run it after the app bundle exists, or with --dry-run to produce the list from the
tracked sources alone.
"""

import argparse
import hashlib
import json
import os
import sys

LIST_NAME = 'resources.txt'
MANIFEST_NAME = 'manifest.json'
HEADER = ('# ballpad-notice-resources/1', 'sha256\tbytes\tpath')


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def shippable_notices(repo_root, manifest_path):
    '''Notice files the bundle must carry, in manifest order.

    The directory index travels too, so a reader who opens notices/ in the bundle sees
    the same explanation the repository shows.
    '''
    with open(manifest_path) as handle:
        manifest = json.load(handle)
    relative = []
    for component in manifest.get('components', []):
        for entry in component.get('notices', []) or []:
            clean = entry[len('notices/'):] if entry.startswith('notices/') else entry
            clean = os.path.normpath(clean)
            if clean not in relative:
                relative.append(clean)
    index = 'README.md'
    if os.path.isfile(os.path.join(repo_root, 'notices', index)) and index not in relative:
        relative.append(index)
    return manifest, relative


def main():
    parser = argparse.ArgumentParser(description='Assemble notices into an app bundle.')
    parser.add_argument('--repo-root', required=True)
    parser.add_argument('--manifest', required=True)
    parser.add_argument('--bundle', required=True)
    parser.add_argument('--platform', default='')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()

    source_dir = os.path.join(args.repo_root, 'notices')
    if not os.path.isdir(source_dir):
        sys.stderr.write('no notices directory at {0}\n'.format(source_dir))
        return 1
    if not os.path.isfile(args.manifest):
        sys.stderr.write('no manifest at {0}\n'.format(args.manifest))
        return 1

    _manifest, relative = shippable_notices(args.repo_root, args.manifest)
    if not relative:
        sys.stderr.write('the manifest claims no notice files; refusing to write an empty list\n')
        return 1

    missing = [rel for rel in relative
               if not os.path.isfile(os.path.join(source_dir, rel))]
    if missing:
        sys.stderr.write('tracked notices are missing: {0}\n'.format(', '.join(missing)))
        return 1

    target_dir = os.path.join(args.bundle, 'notices')
    if not args.dry_run:
        if not os.path.isdir(args.bundle):
            sys.stderr.write('bundle does not exist: {0}\n'.format(args.bundle))
            return 1
        if not os.path.isdir(target_dir):
            os.makedirs(target_dir)

    rows = []
    for rel in relative:
        src = os.path.join(source_dir, rel)
        with open(src, 'rb') as handle:
            payload = handle.read()
        digest = hashlib.sha256(payload).hexdigest()
        if not args.dry_run:
            dst = os.path.join(target_dir, rel)
            parent = os.path.dirname(dst)
            if parent and not os.path.isdir(parent):
                os.makedirs(parent)
            with open(dst, 'wb') as handle:
                handle.write(payload)
        rows.append((digest, len(payload), rel))

    manifest_digest = sha256_of(args.manifest)
    if not args.dry_run:
        with open(args.manifest, 'rb') as handle:
            manifest_bytes = handle.read()
        with open(os.path.join(target_dir, MANIFEST_NAME), 'wb') as handle:
            handle.write(manifest_bytes)
        lines = list(HEADER)
        if args.platform:
            lines.append('# platform: ' + args.platform)
        lines.append('# manifest: docs/native-strikers-dependency-manifest.json')
        lines.append('# manifest-sha256: ' + manifest_digest)
        for digest, size, rel in rows:
            lines.append('{0}\t{1}\t{2}'.format(digest, size, rel))
        with open(os.path.join(target_dir, LIST_NAME), 'w') as handle:
            handle.write('\n'.join(lines) + '\n')

    for digest, size, rel in rows:
        sys.stdout.write('   ok {0}  {1}  {2}\n'.format(digest[:12], size, rel))
    if args.dry_run:
        sys.stdout.write('notice resources: {0} file(s) would be placed\n'.format(len(rows)))
    else:
        sys.stdout.write('notice resources: {0} file(s) placed in {1}\n'.format(len(rows), target_dir))
    return 0


if __name__ == '__main__':
    sys.exit(main())

