package funkfmpeg;

import haxe.io.Bytes;

class Tape {
    /** Creates one continuous horizontal indexed PNG strip from an ordered frame list. */
    public static function create(frames:Array<String>, outputPath:String, ?options:TapeOptions):TapeResult {
        if (options == null) options = new TapeOptions();
        if (frames == null || frames.length == 0) throw "FunkFMPEG: no input frames";
        if (outputPath == null || outputPath.length == 0) throw "FunkFMPEG: output path is empty";
        if (options.compression < 0 || options.compression > 9) throw "FunkFMPEG: compression must be between 0 and 9";
        if (options.colors < 2 || options.colors > 256) throw "FunkFMPEG: colors must be between 2 and 256";

        var first = PngImage.read(frames[0]);
        var dimensions = FrameScale.dimensions(first.width, first.height, frames.length, options);
        var frameWidth = dimensions[0];
        var frameHeight = dimensions[1];
        var sheetWidthFloat:Float = frameWidth * 1.0 * frames.length;
        var sheetHeight = frameHeight;
        var rawSize:Float = (sheetWidthFloat + 1) * sheetHeight;
        if (options.maxWidth > 0 && sheetWidthFloat > options.maxWidth) throw 'FunkFMPEG: strip width ${sheetWidthFloat} exceeds maxWidth ${options.maxWidth}. Use scaleDivisor = 0 (auto) or increase scaleDivisor.';
        if (options.maxHeight > 0 && sheetHeight > options.maxHeight) throw 'FunkFMPEG: strip height ${sheetHeight} exceeds maxHeight ${options.maxHeight}.';
        if (sheetWidthFloat > 2147483000 || sheetHeight > 2147483000 || rawSize > 2147483000) {
            throw 'FunkFMPEG: strip is too large for one Haxe Bytes buffer (${sheetWidthFloat}x${sheetHeight}). Increase scaleDivisor.';
        }
        var sheetWidth = Std.int(sheetWidthFloat);
        var scanlineStride = sheetWidth + 1;

        if (options.onProgress != null) options.onProgress(0);
        var built = PaletteBuilder.build(frames, frameWidth, frameHeight, first.width, first.height, options);
        var palette = built.colors;
        var lookup = built.lookup;
        var keepAlpha = options.keepAlpha;

        // PNG scanlines include their filter byte. Filling this buffer directly avoids
        // allocating a second full-size index buffer for the spritesheet.
        var scanlines = Bytes.alloc(Std.int(rawSize));
        for (y in 0...sheetHeight) scanlines.set(y * scanlineStride, 0);

        var frameNumber = 0;
        for (path in frames) {
            var image = PngImage.read(path);
            if (image.width != first.width || image.height != first.height) {
                throw 'FunkFMPEG: frame dimensions differ. Expected ${first.width}x${first.height}, got ${image.width}x${image.height}: $path';
            }
            var pixels = FrameScale.resize(image, frameWidth, frameHeight, options.background, options.keepAlpha);
            var frameX = frameNumber * frameWidth;
            var p = 0;
            for (y in 0...frameHeight) {
                var dst = y * scanlineStride + 1 + frameX;
                for (x in 0...frameWidth) {
                    var r = pixels.get(p);
                    var g = pixels.get(p + 1);
                    var b = pixels.get(p + 2);
                    var a = pixels.get(p + 3);
                    scanlines.set(dst + x, lookup.get(PaletteBuilder.key(r, g, b, a, keepAlpha)));
                    p += 4;
                }
            }
            frameNumber++;
            if (options.onProgress != null) options.onProgress(42 + Std.int(frameNumber * 53 / frames.length));
        }

        PngImage.writeIndexedScanlines(outputPath, sheetWidth, sheetHeight, scanlines, palette, options.compression);
        if (options.onProgress != null) options.onProgress(100);
        return new TapeResult(sheetWidth, sheetHeight, frameWidth, frameHeight, frames.length, palette.length, options.keepAlpha);
    }
}
