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

## Resulting license and open obligations

With GPL and nonfree components disabled, this configuration is offered under the
GNU Lesser General Public License, version 2.1 or later; the verbatim text ships
alongside this note as `COPYING.LGPLv2.1`. Because the app links FFmpeg statically,
LGPL section 6 applies: a distributor must also convey the means to relink the
application with a modified version of the library. Publishing the exact upstream
archive, its hash and the configure line above is necessary but is not a complete
discharge of that obligation.

Tracked as unresolved:

- no formal written offer and relinkable object set is packaged with any binary yet;
- no corresponding-source archive is bundled with any binary yet;
- the macOS Homebrew `libavcodec` used for desktop reference runs is a separate
  distribution question from the static mobile build and is not shipped.

Nothing here should be read as a claim that including a license file completes
compliance, or that a THP-only static library has no obligations.

