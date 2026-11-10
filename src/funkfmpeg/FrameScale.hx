package funkfmpeg;

import haxe.ds.Vector;
import haxe.io.Bytes;

/** Per-axis resampling weights: output i reads source taps start[i] ... start[i] + weights[i].length - 1. */
private class Axis {
    public var start:Array<Int> = [];
    public var weights:Array<Array<Float>> = [];

    public function new(srcSize:Int, dstSize:Int) {
        if (dstSize >= srcSize) {
            // Upscale (or same size): bilinear, pixel-center aligned. Same size is an exact copy.
            for (i in 0...dstSize) {
                var s = ((i + 0.5) * srcSize / dstSize) - 0.5;
                var i0 = Std.int(Math.floor(s));
                var f = s - i0;
                if (i0 < 0) { i0 = 0; f = 0; }
                var i1 = i0 + 1;
                if (i1 >= srcSize) i1 = srcSize - 1;
                if (i1 == i0 || f <= 0) { start.push(i0); weights.push([1.0]); }
                else { start.push(i0); weights.push([1 - f, f]); }
            }
        } else {
            // Downscale: exact box (area) average over the source span. Uses every source pixel,
            // so thin lines and small details are averaged instead of skipped like bilinear does.
            for (i in 0...dstSize) {
                var s0 = i * 1.0 * srcSize / dstSize;
                var s1 = (i + 1) * 1.0 * srcSize / dstSize;
                var first = Std.int(Math.floor(s0));
                var last = Std.int(Math.ceil(s1)) - 1;
                if (last >= srcSize) last = srcSize - 1;
                if (last < first) last = first;
                var w:Array<Float> = [];
                var sum = 0.0;
                for (j in first...(last + 1)) {
                    var lo = j > s0 ? j : s0;
                    var hi = (j + 1) < s1 ? (j + 1) : s1;
                    var v = hi - lo;
                    if (v < 0) v = 0;
                    w.push(v);
                    sum += v;
                }
                if (sum <= 0) { w = [1.0]; sum = 1.0; }
                for (k in 0...w.length) w[k] /= sum;
                start.push(first);
                weights.push(w);
            }
        }
    }
}

class FrameScale {
    /** Largest Bytes buffer Haxe can allocate safely (Int32). */
    public static inline var HARD_LIMIT:Float = 2147483000;

    /**
     * Returns [frameWidth, frameHeight].
     * - frameWidth > 0: fixed width, aspect preserved.
     * - scaleDivisor > 0: fixed divisor.
     * - otherwise AUTO: the biggest frame that keeps the whole strip inside every limit.
     */
    public static function dimensions(width:Int, height:Int, frameCount:Int, options:TapeOptions):Array<Int> {
        if (width <= 0 || height <= 0) throw "FunkFMPEG: invalid input frame dimensions";
        if (frameCount <= 0) throw "FunkFMPEG: invalid frame count";
        if (options.frameWidth > 0) {
            var w:Float = options.frameWidth;
            return [evenFloor(w), evenFloor(height * (w / width))];
        }
        if (options.scaleDivisor > 0) {
            return [evenFloor(width / options.scaleDivisor), evenFloor(height / options.scaleDivisor)];
        }
        return fit(width, height, frameCount, options);
    }

    /** AUTO mode: binary search for the largest frame width (<= source width) whose strip is allowed. */
    public static function fit(width:Int, height:Int, frameCount:Int, options:TapeOptions):Array<Int> {
        var byteLimit:Float = (options.maxBytes > 0 && options.maxBytes < HARD_LIMIT) ? options.maxBytes : HARD_LIMIT;
        var allowed = function(fw:Int):Bool {
            var fh = heightFor(width, height, fw);
            var stripW:Float = fw * 1.0 * frameCount;
            if (stripW > HARD_LIMIT) return false;
            if (options.maxWidth > 0 && stripW > options.maxWidth) return false;
            if (options.maxHeight > 0 && fh > options.maxHeight) return false;
            if (options.maxPixels > 0 && stripW * fh > options.maxPixels) return false;
            return (stripW + 1) * fh <= byteLimit;
        };
        if (!allowed(1)) throw 'FunkFMPEG: $frameCount frames cannot fit inside the given limits even at 1px wide (maxWidth/maxHeight/maxBytes)';
        var lo = 1;
        var hi = width;
        while (lo < hi) {
            var mid = lo + ((hi - lo + 1) >> 1);
            if (allowed(mid)) lo = mid; else hi = mid - 1;
        }
        return [lo, heightFor(width, height, lo)];
    }

    static inline function heightFor(width:Int, height:Int, fw:Int):Int {
        if (fw == width) return height;
        var h = Std.int(Math.floor(height * fw / width + 0.5));
        return h < 1 ? 1 : h;
    }

    static function evenFloor(value:Float):Int {
        if (!Math.isFinite(value) || value > 2147483000) throw "FunkFMPEG: scaled frame dimension is too large";
        var n = Std.int(Math.floor(value));
        if (n < 2) n = 2;
        return n & ~1;
    }

    /**
     * High quality resize. Downscaling uses an exact area average (every source pixel counts),
     * upscaling uses bilinear. Alpha mode averages premultiplied RGB to avoid dark/colored fringes.
     * Same-size input is copied exactly.
     */
    public static function resize(image:PngImage, width:Int, height:Int, background:Int, keepAlpha:Bool):Bytes {
        var pixelCount:Float = width * 1.0 * height;
        if (pixelCount * 4 > HARD_LIMIT) throw "FunkFMPEG: resized frame is too large for a Haxe Bytes buffer";
        var sw = image.width;
        var sh = image.height;
        var src = image.rgba;
        var bgR = (background >> 16) & 255;
        var bgG = (background >> 8) & 255;
        var bgB = background & 255;
        var output = Bytes.alloc(width * height * 4);

        // Fast path: nothing to resample.
        if (width == sw && height == sh) {
            if (keepAlpha) {
                output.blit(0, src, 0, width * height * 4);
                var q = 0;
                while (q < output.length) {
                    if (output.get(q + 3) == 0) { output.set(q, 0); output.set(q + 1, 0); output.set(q + 2, 0); }
                    q += 4;
                }
            } else {
                var q = 0;
                while (q < output.length) {
                    var a = src.get(q + 3);
                    if (a == 255) {
                        output.set(q, src.get(q)); output.set(q + 1, src.get(q + 1)); output.set(q + 2, src.get(q + 2));
                    } else {
                        output.set(q, clampByte(composite(src.get(q), a, bgR)));
                        output.set(q + 1, clampByte(composite(src.get(q + 1), a, bgG)));
                        output.set(q + 2, clampByte(composite(src.get(q + 2), a, bgB)));
                    }
                    output.set(q + 3, 255);
                    q += 4;
                }
            }
            return output;
        }

        var ax = new Axis(sw, width);
        var ay = new Axis(sh, height);

        // Pass 1 (horizontal): sh rows x width columns x 4 channels, in premultiplied/composited float space.
        var tmp = new Vector<Float>(width * sh * 4);
        for (y in 0...sh) {
            var rowBase = y * sw;
            for (x in 0...width) {
                var w = ax.weights[x];
                var s0 = ax.start[x];
                var c0 = 0.0, c1 = 0.0, c2 = 0.0, c3 = 0.0;
                for (k in 0...w.length) {
                    var p = (rowBase + s0 + k) * 4;
                    var wt = w[k];
                    var a = src.get(p + 3);
                    if (keepAlpha) {
                        var pa = wt * a / 255.0;
                        c0 += src.get(p) * pa;
                        c1 += src.get(p + 1) * pa;
                        c2 += src.get(p + 2) * pa;
                        c3 += wt * a;
                    } else if (a == 255) {
                        c0 += src.get(p) * wt;
                        c1 += src.get(p + 1) * wt;
                        c2 += src.get(p + 2) * wt;
                    } else {
                        c0 += composite(src.get(p), a, bgR) * wt;
                        c1 += composite(src.get(p + 1), a, bgG) * wt;
                        c2 += composite(src.get(p + 2), a, bgB) * wt;
                    }
                }
                var t = (y * width + x) * 4;
                tmp[t] = c0; tmp[t + 1] = c1; tmp[t + 2] = c2; tmp[t + 3] = c3;
            }
        }

        // Pass 2 (vertical) + write bytes.
        for (y in 0...height) {
            var w = ay.weights[y];
            var s0 = ay.start[y];
            for (x in 0...width) {
                var c0 = 0.0, c1 = 0.0, c2 = 0.0, c3 = 0.0;
                for (k in 0...w.length) {
                    var t = ((s0 + k) * width + x) * 4;
                    var wt = w[k];
                    c0 += tmp[t] * wt;
                    c1 += tmp[t + 1] * wt;
                    c2 += tmp[t + 2] * wt;
                    c3 += tmp[t + 3] * wt;
                }
                var d = (y * width + x) * 4;
                if (keepAlpha) {
                    if (c3 <= 0.0001) {
                        output.set(d, 0); output.set(d + 1, 0); output.set(d + 2, 0); output.set(d + 3, 0);
                    } else {
                        var inv = 255.0 / c3;
                        output.set(d, clampByte(c0 * inv));
                        output.set(d + 1, clampByte(c1 * inv));
                        output.set(d + 2, clampByte(c2 * inv));
                        output.set(d + 3, clampByte(c3));
                    }
                } else {
                    output.set(d, clampByte(c0));
                    output.set(d + 1, clampByte(c1));
                    output.set(d + 2, clampByte(c2));
                    output.set(d + 3, 255);
                }
            }
        }
        return output;
    }

    static inline function composite(value:Int, alpha:Int, background:Int):Float {
        return (value * alpha + background * (255 - alpha)) / 255.0;
    }

    static inline function clampByte(value:Float):Int {
        if (value <= 0) return 0;
        if (value >= 255) return 255;
        return Std.int(value + 0.5);
    }
}
