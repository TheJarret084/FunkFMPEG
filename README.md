# FunkFMPEG

**FunkFMPEG** is a library to make indexed PNG, writing, and compression use Haxe code and the Haxe standard library.

## Features

- Reads numbered PNG frames from a folder or an explicit list of paths.
- Creates exactly one horizontal strip: frame 1, frame 2, frame 3, and so on.
- **Auto mode (default): always uses the largest frame size allowed** by your limits (`maxWidth`, `maxHeight`, `maxBytes`, Haxe buffer limit). Never upscales past the source.
- High quality downscaling: exact area averaging (every source pixel counts), premultiplied alpha.
- Builds one global palette from every frame, keeping colors consistent across the strip.
- Median-cut palette quantization with 2 to 256 colors, refined with k-means passes and a finer histogram (6 bits per channel).
- Writes an 8-bit indexed PNG (PNG color type 3).
- Optional alpha preservation through the PNG `tRNS` palette transparency chunk.
- When alpha is disabled, composites transparent pixels over a configurable background (black by default).
- Optional `palette.png` and RGBA `palette.txt` exports.
- Writes the PNG scanline buffer directly, avoiding a second full-size index buffer.
- No Haxelib dependencies.

## Install locally

From the FunkFMPEG directory:

```sh
haxelib dev funkfmpeg .
```

Then use it in a Haxe project:

```sh
haxe -lib funkfmpeg ...
```

## CLI

The included CLI sorts PNG filenames lexicographically. Use zero-padded frame names such as `frame_000001.png` so they remain in the correct order.

```sh
haxe -cp src --run funkfmpeg.cli.Main frames filmstrip.png auto 256 false 16384
```

Arguments:

```text
<frames-folder> <output.png> [scale-divisor|auto] [colors] [keep-alpha] [max-width] [max-height]
```

- `scale-divisor`: `auto` (default, or `0`) = biggest frame allowed. A number like `3` means one-third width and height.
- `colors`: maximum number of colors, from `2` to `256`. Default: `256`.
- `keep-alpha`: `true` or `false`. Default: `false`.
- `max-width` / `max-height`: limit of the final strip in pixels (`0` = no limit). Use your GPU texture limit here, for example `16384`.

The CLI also writes `palette.png` and `palette.txt` to the current working directory.

## Haxe API

```haxe
import funkfmpeg.FunkFMPEG;
import funkfmpeg.TapeOptions;

var frames = [
    "frames/frame_000001.png",
    "frames/frame_000002.png",
    "frames/frame_000003.png"
];

var options = new TapeOptions();
options.scaleDivisor = 0;        // 0 = AUTO: biggest frame that fits the limits (default)
options.maxWidth = 16384;       // strip limit, for example the GPU texture size (0 = none)
options.colors = 256;
options.compression = 9;
options.keepAlpha = false;       // true preserves source alpha
options.background = 0x000000;   // used only when keepAlpha is false
options.palettePath = "palette.png";
options.paletteTextPath = "palette.txt";
options.onProgress = function(percent) Sys.println(percent + "%");

var result = FunkFMPEG.create(frames, "filmstrip.png", options);
Sys.println(result.width + "x" + result.height);
```

### Options

| Field | Default | Meaning |
|---|---:|---|
| `scaleDivisor` | `0` | `0` = AUTO (largest allowed frame, no upscale). `3` means 1/3 size. |
| `maxWidth` | `0` | AUTO: max strip width in pixels (`0` = only the Haxe buffer limit). |
| `maxHeight` | `0` | AUTO: max strip height in pixels (`0` = no limit). |
| `maxPixels` | `84800000` | AUTO: max strip area (width x height). Default equals a 264920x320 strip. `0` = no limit. |
| `maxBytes` | `0` | AUTO: max raw strip buffer, `(width + 1) * height` (`0` = ~2 GB Haxe limit). |
| `refine` | `4` | K-means refinement passes on the palette. `0` disables. |
| `frameWidth` | `0` | Optional fixed output frame width. Preserves aspect ratio and overrides `scaleDivisor`. |
| `colors` | `256` | Maximum global palette size, from 2 to 256. |
| `compression` | `9` | PNG compression level, from 0 to 9. |
| `keepAlpha` | `false` | Preserve alpha in the indexed PNG. |
| `background` | `0x000000` | RGB compositing background when alpha is disabled. |
| `palettePath` | `null` | Optional indexed PNG palette export. |
| `paletteTextPath` | `null` | Optional RGBA text palette, one `R,G,B,A` entry per line. |
| `onProgress` | `null` | Optional callback receiving progress from 0 to 100. |

### Result

`TapeResult` provides:

- `width`, `height`: final single-strip dimensions.
- `frameWidth`, `frameHeight`: dimensions of an individual resized frame.
- `frameCount`: number of frames in the strip.
- `paletteSize`: number of colors actually used.
- `hasAlpha`: whether alpha preservation was requested.

## Auto mode

Frames are placed edge to edge: no gaps, no padding, no cropping. Frame N starts exactly at x = N * frameWidth.

With `scaleDivisor = 0` the library binary-searches the biggest frame width (up to the source width) where the whole strip stays inside `maxWidth`, `maxHeight`, `maxBytes` and the Haxe `Bytes` limit. Example with 12 frames of 1920x1080 and `maxWidth = 8192`: frames become `682x384`, strip `8184x384`. With no limits, 4 frames stay at full `1920x1080`.

If you pass `maxWidth` the engine can load, the result is always the sharpest strip that engine accepts.

## Example: 414 frames at 1920x1080

With `scaleDivisor = 3`:

- Each frame becomes `640x360`.
- All 414 frames are placed in one row.
- The strip becomes `264960x360`.
- Palette contains up to 256 colors.

**Large-strip warning:** a horizontal strip gets very wide. PNG permits large dimensions, but image viewers, GPU textures, and some decoders impose much smaller width limits. The library also needs a scanline buffer proportional to the final strip size. Increase `scaleDivisor` if memory or decoder limits become a problem.

## Alpha behavior

- `keepAlpha = false`: every pixel becomes opaque. Transparent input pixels are composited over `background` before palette generation.
- `keepAlpha = true`: alpha is resized with premultiplied-alpha interpolation and quantized into the shared RGBA palette. The PNG stores palette transparency using `tRNS`.

The RGBA palette is limited to the same total maximum of 256 entries. It is not a full 256-color RGB palette plus a separate alpha table.

## Input limitations

- Input PNGs must be 8-bit and non-interlaced.
- RGB, RGBA, grayscale, grayscale-alpha, and indexed PNG inputs are supported.
- Frames must all have the same dimensions.
- Downscaling uses exact area averaging, upscaling uses bilinear. It preserves proportions but does not recover detail lost in the source video.
- Palette generation uses a fixed-size histogram, weighted median cut and k-means refinement; indices are looked up from the real average color of each histogram cell. `colors` is a maximum, not a requirement to invent colors.

## License

MIT. See [LICENSE](LICENSE).
