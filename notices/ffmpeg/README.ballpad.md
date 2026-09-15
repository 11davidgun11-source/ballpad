# FFmpeg in the Ballpad native build

This note records what FFmpeg the app actually links, how it was configured, and which
obligations that configuration leaves open. It is part of the shipped notice set, so it
travels with the binary rather than only living in the build scripts.

## What the engine uses FFmpeg for

The port calls exactly one FFmpeg entry point: `avcodec_find_decoder(AV_CODEC_ID_THP)`
followed by a decode of each video packet from its own demuxer. The THP container parser
and the DSP-ADPCM audio decoder are the port's own code in `smstrikers-port/src/platform/thp.c`.
Consequently `libavformat`, `libavfilter`, `libavdevice`, `libswscale` and `libswresample`
are not needed and are not linked.

## Pinned source

| Field | Value |
| --- | --- |
| Upstream | https://ffmpeg.org/ |
| Release | 9.0.1 |
| Archive | https://ffmpeg.org/releases/ffmpeg-9.0.1.tar.xz |
| Archive SHA-256 | `cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635` |
| Built artifacts | `build/native/deps/ffmpeg/<platform>/lib/libavcodec.a`, `libavutil.a` |
| Build stamp | `build/native/deps/ffmpeg/<platform>/.ballpad-ffmpeg` holds the archive SHA-256 |

The macOS reference build used by desktop runs is the host Homebrew `libavcodec` instead,
and must never enter a Simulator or device link line. The mobile builds use only the
static libraries described here.

## Exact configure invocation

`scripts/native/bootstrap.sh` (`prepare_ffmpeg`) runs, for an iOS target:

```sh
./configure \
    --prefix="$OUT" --cc="$(xcrun --find clang)" \
    --enable-cross-compile --target-os=darwin --arch=arm64 \
    --enable-static --disable-shared --enable-pic --disable-asm \
    --disable-autodetect --disable-programs --disable-doc --disable-network \
    --disable-avformat --disable-avfilter --disable-avdevice \
    --disable-swscale --disable-swresample \
    --disable-everything --enable-decoder=thp \
    --extra-cflags="-arch arm64 -isysroot $SDK -O2 -fPIC $TARGET" \
    --extra-ldflags="-arch arm64 -isysroot $SDK -O2 -fPIC $TARGET"
```

where `$TARGET` is `-target arm64-apple-ios17.0-simulator` for the Simulator and
`-target arm64-apple-ios17.0` for device, and `$SDK` comes from `xcrun --sdk
iphonesimulator|iphoneos --show-sdk-path`. `--disable-postproc` was removed from this
list because FFmpeg 9.0.1 no longer carries that option and aborted configure when it
was passed.

Enabled components in this configuration are the FFmpeg core, `libavutil` and
`libavcodec` with a single decoder (`thp`). Every optional external library is off,
both through `--disable-autodetect` and through `--disable-everything`. There is no
`--enable-gpl` and no `--enable-nonfree`.

## Resulting license

With GPL and nonfree components disabled, this configuration is offered under the
GNU Lesser General Public License, version 2.1 or later; the verbatim text ships
alongside this note as `COPYING.LGPLv2.1`. The requirement LGPL 2.1 section 6 adds
to a statically linked work is that the recipient must also be able to modify the
library and relink the application. This note, the license text and the configure
line record that obligation; they do not carry the material that satisfies it.

## The material that does satisfy it

`scripts/native/ffmpeg-relink-offer.sh` assembles that material for one platform from
the build that exists, so the packaged set describes the link the app actually shipped
with rather than a remembered one. It writes
`build/native/n7/ffmpeg-relink-offer/<platform>/`:

| File | What it is |
| --- | --- |
| `CORRESPONDING-SOURCE.md` | Which FFmpeg, from where, with which hash, and the exact configure line. FFmpeg is unmodified, so the pinned upstream archive plus that line is its complete corresponding source. |
| `LINK-COMMAND.txt` | The link command ninja itself prints for the app target, captured rather than reconstructed by hand. |
| `LINK-INPUTS.tsv` | Every object, archive and SDK stub on that command with its SHA-256 and size, so a relink can be checked instead of trusted. |
| `ffmpeg-relink.sh` | `scripts/native/lib/ffmpeg-relink.sh` re-runs the captured command with a substitute `libavcodec.a`/`libavutil.a`, which is what lets a modified FFmpeg be relinked. It refuses to write over the shipped executable. |
| `offer.env` | The build directory, target and pinned archive paths the relinker reads. |

The packaging step was exercised against the pinned libraries and is not a promise:
`--exercise` relinked the app from the packaged command and the result was a Mach-O
arm64 `iossimulator` executable **byte-identical** to the shipped one
(`e5d4d1a2fa3c5982a64226adaf8186c747cf49eb10c69cb1e4d254cda7026224`, 16,698,400 bytes),
over 674 link inputs of which the two FFmpeg archives are the only ones the offer
substitutes.

## What this still does not do

- It packages material; it distributes nothing. This is a local development build and
  no binary leaves this machine under the task's authorization boundary.
- It does not by itself make any distributed binary compliant: a binary that ships
  without this set alongside it is not accompanied by the section 6 material, which is
  why `docs/native-strikers-release-readiness.md` keeps distribution a separate,
  still-open decision rather than folding it into attribution.
- The macOS Homebrew `libavcodec` used for desktop reference runs is a separate
  distribution question from the static mobile build and is not part of this set.

Nothing here should be read as a claim that including a license file completes
compliance, or that a THP-only static library has no obligations.
