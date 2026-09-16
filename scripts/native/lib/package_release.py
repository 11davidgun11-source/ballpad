#!/usr/bin/env python3
"""Package an unsigned device app and portable source/relink materials. No publication."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import zipfile


def run(*args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def checksums(root):
    entries = [p for p in sorted(root.rglob('*')) if p.is_file() and p.name != 'SHA256SUMS']
    (root / 'SHA256SUMS').write_text(''.join(f'{digest(p)}  {p.relative_to(root)}\n' for p in entries))


def archive_tree(source, destination, prefix):
    def include(info):
        if any(part in {'.git', '__pycache__', '.DS_Store'} for part in Path(info.name).parts):
            return None
        info.uid = info.gid = 0
        info.uname = info.gname = ''
        return info
    with tarfile.open(destination, 'w:gz') as archive:
        archive.add(source, arcname=prefix, filter=include)


def git_archive(repo, revision, destination, prefix):
    subprocess.run(['git', '-C', str(repo), 'archive', '--format=tar.gz',
                    '--prefix=' + prefix + '/', '--output=' + str(destination), revision], check=True)


def portable_link(args, output):
    build = args.root / 'build/native/device-release'
    binary = build / 'port/BallpadStrikers.app/BallpadStrikers'
    raw = run('ninja', '-C', str(build), '-t', 'commands', str(binary.relative_to(build))).splitlines()[-1]
    tokens = shlex.split(raw)
    if tokens[:2] != [':', '&&'] or tokens[-2:] != ['&&', ':']:
        raise RuntimeError('unrecognized Ninja link wrapper; inspect before packaging')
    tokens = tokens[2:-2]
    if any(t in {'&&', ';', '|', '>'} or t.startswith('@') for t in tokens):
        raise RuntimeError('unsupported compound link or response file')
    sdk_index = tokens.index('-isysroot') + 1
    sdk = Path(tokens[sdk_index])
    tokens[0] = '${CXX}'
    tokens[sdk_index] = '${SDK}'
    tokens[tokens.index('-o') + 1] = '${OUTPUT}'
    folder = output / 'relink'
    (folder / 'inputs').mkdir(parents=True)
    manifest = {'argv': [], 'inputs': [], 'sdk': 'iphoneos', 'shipped_binary_sha256': digest(binary),
                'engine_commit': args.engine_pin, 'engine_tree': args.engine_tree,
                'app_source_ref': args.source_ref, 'release_material': not args.relink_only}
    copied = {}
    for token in tokens:
        if token.startswith(str(sdk) + '/'):
            token = '${SDK}/' + str(Path(token).relative_to(sdk))
        elif token.endswith(('.o', '.a')):
            path = Path(token)
            path = (path if path.is_absolute() else build / path).resolve()
            if not path.is_file():
                raise RuntimeError('missing link input: ' + str(path))
            if path not in copied:
                relative = f'inputs/{len(copied):04d}-{path.name}'
                shutil.copyfile(path, folder / relative)
                copied[path] = relative
                manifest['inputs'].append({'path': relative, 'sha256': digest(path), 'bytes': path.stat().st_size})
            token = copied[path]
            if path.name in {'libavcodec.a', 'libavutil.a'}:
                key = 'avcodec' if path.name == 'libavcodec.a' else 'avutil'
                manifest[key] = token
                token = '${' + key.upper() + '}'
        elif token.startswith('/') or token.endswith(('.tbd', '.dylib', '.so')):
            raise RuntimeError('unpackaged absolute/nonstatic input: ' + token)
        manifest['argv'].append(token)
    if not {'avcodec', 'avutil'} <= manifest.keys():
        raise RuntimeError('captured link does not include both FFmpeg archives')
    (folder / 'link.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (folder / 'LINK-COMMAND.txt').write_text('# Ninja link command, normalized to packaged inputs and recipient Xcode:\n' + shlex.join(manifest['argv']) + '\n')
    shutil.copyfile(Path(__file__).with_name('portable_relink.py'), folder / 'relink.py')
    source = folder / f'ffmpeg-{args.ffmpeg_version}.tar.xz'
    subprocess.run(['curl', '-fL', '--retry', '3', '--silent', '--show-error', args.ffmpeg_url, '-o', str(source)], check=True)
    if digest(source) != args.ffmpeg_sha:
        raise RuntimeError('FFmpeg source checksum mismatch')
    shutil.copyfile(args.root / 'notices/ffmpeg/COPYING.LGPLv2.1', folder / 'COPYING.LGPLv2.1')
    rebuild = '''#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# Edit the extracted source before rerunning configure/make to build a modified library.
[ -d ffmpeg-VERSION ] || tar -xJf ffmpeg-VERSION.tar.xz
prefix="$(pwd)/modified-ffmpeg"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
flags="-arch arm64 -isysroot $sdk -O2 -fPIC -target arm64-apple-iosMINIMUM"
cd ffmpeg-VERSION
./configure --prefix="$prefix" --cc="$(xcrun --sdk iphoneos --find clang)" \\
 --enable-cross-compile --target-os=darwin --arch=arm64 \\
 --enable-static --disable-shared --enable-pic --disable-asm \\
 --disable-autodetect --disable-programs --disable-doc --disable-network \\
 --disable-avformat --disable-avfilter --disable-avdevice \\
 --disable-swscale --disable-swresample --disable-everything --enable-decoder=thp \\
 --extra-cflags="$flags" --extra-ldflags="$flags"
make -j"$(sysctl -n hw.ncpu)"
make install
'''
    (folder / 'build-ffmpeg.sh').write_text(rebuild.replace('VERSION', args.ffmpeg_version).replace('MINIMUM', args.deployment_target))
    (folder / 'README.md').write_text('''# Portable FFmpeg relinking materials

Requires macOS, Xcode with the iPhoneOS SDK, Python 3, and standard command-line tools.
No Apple SDK or signing material is included. All non-Apple inputs to the captured link
are included and checksummed. Paths resolve within this directory; Xcode resolves via xcrun.

Relink the supplied archives: `python3 relink.py --out /absolute/new/path/BallpadStrikers`.
To modify FFmpeg, extract the included archive, edit it, then run `bash build-ffmpeg.sh`.
Relink using `python3 relink.py --avcodec modified-ffmpeg/lib/libavcodec.a
--avutil modified-ffmpeg/lib/libavutil.a --out /absolute/new/path/BallpadStrikers` on one line.
Copy the resulting executable into a copy of the matching unsigned app bundle and sign
that copy for your own device using your own provisioning profile and identity.

The bundled FFmpeg archive is the pinned unmodified upstream source. The build script
uses the original bootstrap configuration with recipient SDK/toolchain/prefix substitutions.
Toolchain changes can change output bytes. Relinkability does not establish legal clearance,
complete offline source closure, or reproducible builds.
''')
    # Exercise after moving the directory. No original build paths are available in the recipe.
    with tempfile.TemporaryDirectory(prefix='ballpad-relocated-') as temporary:
        relocated = Path(temporary) / 'portable materials'
        shutil.move(str(folder), relocated)
        try:
            result = relocated / 'relinked/BallpadStrikers'
            subprocess.run(['python3', str(relocated / 'relink.py'), '--out', str(result)], check=True)
            platform = run('xcrun', 'vtool', '-show-build', str(result))
            if 'platform IOS\n' not in platform:
                raise RuntimeError('relocated executable does not target iOS')
            manifest['relocation_test'] = {'passed': True, 'binary_sha256': digest(result),
                                           'byte_identical': digest(result) == digest(binary)}
            (relocated / 'link.json').write_text(json.dumps(manifest, indent=2) + '\n')
            shutil.rmtree(result.parent)
        finally:
            shutil.move(str(relocated), folder)
    checksums(folder)
    archive_tree(folder, output / 'BallPad-FFmpeg-relink.tar.gz', 'BallPad-relink')
    print('Portable relink PASS:', len(copied), 'copied inputs', flush=True)


def release_sources(args, output):
    if not args.source_ref:
        raise RuntimeError('--source-ref is required for final release source packaging')
    revision = run('git', '-C', str(args.root), 'rev-parse', args.source_ref + '^{commit}')
    if revision != run('git', '-C', str(args.root), 'rev-parse', 'HEAD'):
        raise RuntimeError('source-ref must match current app checkout HEAD')
    if run('git', '-C', str(args.root), 'status', '--porcelain', '--untracked-files=no'):
        raise RuntimeError('tracked app source is dirty; commit final sources before packaging')
    folder = output / 'sources'
    folder.mkdir()
    git_archive(args.root, revision, folder / 'ballpad.tar.gz', 'ballpad')
    git_archive(args.engine, args.engine_pin, folder / 'strikers.tar.gz', 'strikers')
    subprocess.run(['git', '-C', str(args.engine), 'bundle', 'create', str(folder / 'strikers.bundle'), 'HEAD'], check=True)
    subprocess.run(['git', '-C', str(args.engine), 'bundle', 'verify', str(folder / 'strikers.bundle')], check=True)
    snapshots = []
    cache = args.root / 'build/native/deps/src'
    for name in ['SDL3', 'dawn', 'zstd']:
        source = cache / name
        if not source.is_dir():
            raise RuntimeError('missing cached dependency source ' + name)
        target = folder / (name + '.tar.gz')
        archive_tree(source, target, name)
        snapshots.append(target.name)
    for source in sorted((args.root / 'build/native/device-release/_deps').glob('*-src')):
        if source.is_dir():
            target = folder / (source.name + '.tar.gz')
            archive_tree(source, target, source.name)
            snapshots.append(target.name)
    for source in sorted(cache.glob('*.tar.*')):
        shutil.copyfile(source, folder / ('upstream-' + source.name))
    shutil.copyfile(output / 'relink' / f'ffmpeg-{args.ffmpeg_version}.tar.xz', folder / f'ffmpeg-{args.ffmpeg_version}.tar.xz')
    (folder / 'SOURCE-INVENTORY.json').write_text(json.dumps({'app_commit': revision,
        'engine_commit': args.engine_pin, 'engine_tree': args.engine_tree,
        'cache_snapshots': snapshots, 'offline_source_closure': 'not verified'}, indent=2) + '\n')
    (folder / 'README.md').write_text('''# BallPad source material

ballpad.tar.gz and strikers.tar.gz are Git archives of the recorded immutable commits.
Other archives snapshot the dependency sources cached for this build, including Dawn's
populated third-party source directories. Original cached download archives are included
where available. FFmpeg source and configuration are also in the matching relink package.
Extract ballpad.tar.gz. For the included engine source with its Git identity, run
`git clone /absolute/path/strikers.bundle ballpad/work/native/strikers`, then
`git -C ballpad/work/native/strikers checkout --detach <engine_commit>` using the
commit in SOURCE-INVENTORY.json. The bundle retains upstream history and the pin.
Alternatively, normal bootstrap clones the public maintained source fork. The
strikers.tar.gz snapshot is provided separately for convenient inspection. Dependency snapshots are supplied as build/source material, not as
a verified offline bootstrap cache. Apple SDK/compiler tools and game data are excluded.

All archives have checksums. The dependency inventory and notices in the app source give
upstream identities and licenses. Offline source closure and byte-for-byte reconstruction
have not been verified; these materials are not a claim of legal clearance.
''')
    checksums(folder)
    archive_tree(folder, output / 'BallPad-sources.tar.gz', 'BallPad-sources')


def unsigned_ipa(args, output):
    source = args.root / 'build/native/device-release/port/BallpadStrikers.app'
    folder = output / 'ipa/Payload/BallpadStrikers.app'
    shutil.copytree(source, folder)
    forbidden = {'.iso', '.gcm', '.wbfs', '.rvz', '.gci', '.raw', '.pem', '.p12', '.key'}
    for p in list(folder.rglob('*')):
        if p.is_symlink():
            raise RuntimeError('unexpected symlink in app bundle: ' + str(p.relative_to(folder)))
        if p.suffix.lower() in forbidden:
            raise RuntimeError('private/game data in app bundle: ' + p.name)
    for name in ['embedded.mobileprovision', '_CodeSignature']:
        path = folder / name
        if path.is_dir():
            shutil.rmtree(path)
        elif path.exists():
            path.unlink()
    info = plistlib.loads((folder / 'Info.plist').read_bytes())
    binary = folder / info['CFBundleExecutable']
    signed = subprocess.run(['codesign', '-d', str(binary)], capture_output=True).returncode == 0
    if signed:
        subprocess.run(['codesign', '--remove-signature', str(binary)], check=True)
    if subprocess.run(['codesign', '-d', str(binary)], capture_output=True).returncode == 0:
        raise RuntimeError('failed to remove app signature')
    with zipfile.ZipFile(output / 'BallPad-unsigned.ipa', 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted((output / 'ipa').rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(output / 'ipa'))
    shutil.rmtree(output / 'ipa')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['root', 'engine', 'out']:
        parser.add_argument('--' + name, type=Path, required=True)
    for name in ['engine-pin', 'engine-tree', 'ffmpeg-version', 'ffmpeg-sha', 'ffmpeg-url', 'deployment-target']:
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--source-ref')
    parser.add_argument('--relink-only', action='store_true')
    args = parser.parse_args()
    args.root = args.root.resolve()
    args.engine = args.engine.resolve()
    output = args.out.resolve()
    if output.exists():
        parser.error('--out must be a new directory')
    if run('git', '-C', str(args.engine), 'rev-parse', 'HEAD') != args.engine_pin or run('git', '-C', str(args.engine), 'rev-parse', 'HEAD^{tree}') != args.engine_tree:
        parser.error('engine does not match maintained pin/tree')
    if run('git', '-C', str(args.engine), 'status', '--porcelain'):
        parser.error('engine source is dirty')
    if not args.relink_only:
        if not args.source_ref:
            parser.error('--source-ref is required unless --relink-only is used')
        if run('git', '-C', str(args.root), 'status', '--porcelain', '--untracked-files=no'):
            parser.error('tracked app source is dirty; commit final sources before packaging')
    output.mkdir(parents=True)
    portable_link(args, output)
    if not args.relink_only:
        release_sources(args, output)
        unsigned_ipa(args, output)
    # Release downloads are top-level archives; working material directories are retained locally.
    (output / 'SHA256SUMS').write_text(''.join(f'{digest(p)}  {p.name}\n' for p in sorted(output.iterdir()) if p.is_file()))
    print('Local artifacts:', output, flush=True)


if __name__ == '__main__':
    main()
