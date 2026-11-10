package funkfmpeg;

import haxe.ds.Vector;
import haxe.io.Bytes;
import sys.io.File;

class PaletteBuilder {
    /** Histogram size. Opaque = 6 bits per channel, alpha = 5/5/5 bits RGB + 3 bits alpha. Both are 18 bits. */
    public static inline var HIST_SIZE:Int = 262144;

    /** Histogram cell for a pixel. Tape must use this same function when it writes the indices. */
    public static inline function key(r:Int, g:Int, b:Int, a:Int, keepAlpha:Bool):Int {
        return keepAlpha
            ? ((r >> 3) << 13) | ((g >> 3) << 8) | ((b >> 3) << 3) | (a >> 5)
            : ((r >> 2) << 12) | ((g >> 2) << 6) | (b >> 2);
    }

    /** Perceptually weighted squared distance (green counts most). Alpha is weighted high so edges stay clean. */
    static inline function distance(r1:Float, g1:Float, b1:Float, a1:Float, r2:Float, g2:Float, b2:Float, a2:Float, keepAlpha:Bool):Float {
        var dr = r1 - r2;
        var dg = g1 - g2;
        var db = b1 - b2;
        var d = 2.0 * dr * dr + 4.0 * dg * dg + 3.0 * db * db;
        if (keepAlpha) {
            var da = a1 - a2;
            d += 6.0 * da * da;
        }
        return d;
    }

    /** Builds one palette from every resized frame. Frames are decoded one at a time. */
    public static function build(frames:Array<String>, width:Int, height:Int, sourceWidth:Int, sourceHeight:Int, options:TapeOptions):PaletteResult {
        var useAlpha = options.keepAlpha;
        var counts = new Vector<Int>(HIST_SIZE);
        var sumR = new Vector<Float>(HIST_SIZE);
        var sumG = new Vector<Float>(HIST_SIZE);
        var sumB = new Vector<Float>(HIST_SIZE);
        var sumA = new Vector<Float>(HIST_SIZE);
        for (i in 0...HIST_SIZE) { counts[i] = 0; sumR[i] = 0; sumG[i] = 0; sumB[i] = 0; sumA[i] = 0; }

        var frameIndex = 0;
        for (path in frames) {
            var image = PngImage.read(path);
            if (image.width != sourceWidth || image.height != sourceHeight) {
                throw 'FunkFMPEG: frame dimensions differ. Expected ${sourceWidth}x${sourceHeight}, got ${image.width}x${image.height}: $path';
            }
            var pixels = FrameScale.resize(image, width, height, options.background, useAlpha);
            var p = 0;
            var n = pixels.length;
            while (p < n) {
                var r = pixels.get(p);
                var g = pixels.get(p + 1);
                var b = pixels.get(p + 2);
                var a = pixels.get(p + 3);
                var k = key(r, g, b, a, useAlpha);
                counts[k]++;
                sumR[k] += r;
                sumG[k] += g;
                sumB[k] += b;
                if (useAlpha) sumA[k] += a;
                p += 4;
            }
            frameIndex++;
            if (options.onProgress != null) options.onProgress(Std.int(frameIndex * 42 / frames.length));
        }

        var bins:Array<ColorBin> = [];
        for (i in 0...HIST_SIZE) {
            var c = counts[i];
            if (c > 0) {
                bins.push(new ColorBin(
                    Std.int(sumR[i] / c + 0.5),
                    Std.int(sumG[i] / c + 0.5),
                    Std.int(sumB[i] / c + 0.5),
                    useAlpha ? Std.int(sumA[i] / c + 0.5) : 255,
                    c,
                    i
                ));
            }
        }
        if (bins.length == 0) throw "FunkFMPEG: no pixels found while building palette";

        // 1) Median cut.
        var boxes:Array<ColorBox> = [new ColorBox(bins.copy())];
        var wanted = options.colors < 2 ? 2 : (options.colors > 256 ? 256 : options.colors);
        while (boxes.length < wanted) {
            var best = -1;
            var bestScore:Float = -1;
            for (i in 0...boxes.length) {
                var box = boxes[i];
                if (box.colors.length < 2) continue;
                var channel = box.longestChannel(useAlpha);
                var range = channel == 0 ? box.rangeR : (channel == 1 ? box.rangeG : (channel == 2 ? box.rangeB : box.rangeA));
                var score = range * Math.sqrt(box.population);
                if (score > bestScore) { bestScore = score; best = i; }
            }
            if (best < 0) break;
            var other = boxes[best].split(useAlpha);
            if (other == null) break;
            boxes.push(other);
        }

        var palette:Array<Array<Int>> = [];
        for (box in boxes) palette.push(box.average());

        // 2) Refinement: a few Lloyd/k-means passes over the histogram bins (weighted by pixel count).
        //    Median cut gives a good start, this pulls each entry to the true center of the pixels it serves.
        var passes = options.refine < 0 ? 0 : options.refine;
        if (passes > 0 && bins.length > palette.length) {
            var m = palette.length;
            var pr = new Vector<Float>(m), pg = new Vector<Float>(m), pb = new Vector<Float>(m), pa = new Vector<Float>(m);
            for (i in 0...m) { pr[i] = palette[i][0]; pg[i] = palette[i][1]; pb[i] = palette[i][2]; pa[i] = palette[i][3]; }
            var ar = new Vector<Float>(m), ag = new Vector<Float>(m), ab = new Vector<Float>(m), aa = new Vector<Float>(m), aw = new Vector<Float>(m);
            for (pass in 0...passes) {
                for (i in 0...m) { ar[i] = 0; ag[i] = 0; ab[i] = 0; aa[i] = 0; aw[i] = 0; }
                for (bin in bins) {
                    var idx = nearest(bin.r, bin.g, bin.b, bin.a, pr, pg, pb, pa, m, useAlpha);
                    var w:Float = bin.count;
                    ar[idx] += bin.r * w; ag[idx] += bin.g * w; ab[idx] += bin.b * w; aa[idx] += bin.a * w; aw[idx] += w;
                }
                for (i in 0...m) {
                    if (aw[i] > 0) {
                        pr[i] = ar[i] / aw[i]; pg[i] = ag[i] / aw[i]; pb[i] = ab[i] / aw[i];
                        pa[i] = useAlpha ? aa[i] / aw[i] : 255;
                    }
                }
            }
            for (i in 0...m) {
                palette[i] = [clamp255(pr[i]), clamp255(pg[i]), clamp255(pb[i]), useAlpha ? clamp255(pa[i]) : 255];
            }
        }

        // 3) Alpha palettes: transparent entries first so the PNG tRNS chunk stays as short as possible.
        if (useAlpha) palette.sort(function(x, y) return x[3] != y[3] ? x[3] - y[3] : (x[0] + x[1] + x[2]) - (y[0] + y[1] + y[2]));

        // 4) Exact lookup: every populated histogram cell -> nearest palette entry, using the cell's REAL average color.
        var lookup = Bytes.alloc(HIST_SIZE);
        var m = palette.length;
        var qr = new Vector<Float>(m), qg = new Vector<Float>(m), qb = new Vector<Float>(m), qa = new Vector<Float>(m);
        for (i in 0...m) { qr[i] = palette[i][0]; qg[i] = palette[i][1]; qb[i] = palette[i][2]; qa[i] = palette[i][3]; }
        for (bin in bins) lookup.set(bin.key, nearest(bin.r, bin.g, bin.b, bin.a, qr, qg, qb, qa, m, useAlpha));

        if (options.paletteTextPath != null) {
            var lines = new StringBuf();
            for (c in palette) lines.add(c[0] + "," + c[1] + "," + c[2] + "," + c[3] + "\n");
            File.saveContent(options.paletteTextPath, lines.toString());
        }
        if (options.palettePath != null) {
            var palettePixels = Bytes.alloc(palette.length);
            for (i in 0...palette.length) palettePixels.set(i, i);
            PngImage.writeIndexed(options.palettePath, palette.length, 1, palettePixels, palette, options.compression);
        }
        return new PaletteResult(palette, lookup);
    }

    static function nearest(r:Float, g:Float, b:Float, a:Float, pr:Vector<Float>, pg:Vector<Float>, pb:Vector<Float>, pa:Vector<Float>, m:Int, keepAlpha:Bool):Int {
        var best = 0;
        var bestDistance:Float = 1.0e30;
        for (i in 0...m) {
            var d = distance(r, g, b, a, pr[i], pg[i], pb[i], pa[i], keepAlpha);
            if (d < bestDistance) { bestDistance = d; best = i; if (d == 0) break; }
        }
        return best;
    }

    static inline function clamp255(v:Float):Int {
        if (v <= 0) return 0;
        if (v >= 255) return 255;
        return Std.int(v + 0.5);
    }
}
