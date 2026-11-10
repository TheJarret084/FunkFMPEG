package funkfmpeg;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.zip.Uncompress;
import haxe.zip.Compress;
import haxe.io.Output;
import sys.io.File;

/** Small, dependency-free 8-bit PNG reader and indexed-PNG writer. */
class PngImage {
    public var width:Int;
    public var height:Int;
    public var rgba:Bytes;

    public function new(width:Int, height:Int, rgba:Bytes) {
        this.width = width;
        this.height = height;
        this.rgba = rgba;
    }

    public static function read(path:String):PngImage {
        var file = File.getBytes(path);
        if (file.length < 33 || file.get(0) != 137 || file.getString(1, 3) != "PNG" || file.get(4) != 13 || file.get(5) != 10 || file.get(6) != 26 || file.get(7) != 10) {
            throw 'FunkFMPEG: not a PNG file: $path';
        }
        var pos = 8;
        var width = 0;
        var height = 0;
        var bitDepth = 0;
        var colorType = 0;
        var interlace = 0;
        var palette:Bytes = null;
        var transparency:Bytes = null;
        var idat = new BytesBuffer();
        var sawHeader = false;
        var sawEnd = false;

        while (pos + 12 <= file.length) {
            var len = readU32(file, pos);
            pos += 4;
            if (len < 0) throw 'FunkFMPEG: invalid PNG chunk length in $path';
            var kind = file.getString(pos, 4);
            pos += 4;
            if (pos + len + 4 > file.length) throw 'FunkFMPEG: corrupt PNG chunk in $path';
            if (kind == "IHDR") {
                if (len != 13) throw 'FunkFMPEG: invalid IHDR chunk in $path';
                width = readU32(file, pos);
                height = readU32(file, pos + 4);
                bitDepth = file.get(pos + 8);
                colorType = file.get(pos + 9);
                interlace = file.get(pos + 12);
                sawHeader = true;
            } else if (kind == "PLTE") {
                palette = file.sub(pos, len);
            } else if (kind == "tRNS") {
                transparency = file.sub(pos, len);
            } else if (kind == "IDAT") {
                idat.addBytes(file, pos, len);
            }
            pos += len + 4; // chunk payload + CRC
            if (kind == "IEND") { sawEnd = true; break; }
        }

        if (!sawHeader || !sawEnd || width <= 0 || height <= 0) throw 'FunkFMPEG: incomplete or invalid PNG: $path';
        if (bitDepth != 8 || interlace != 0) throw 'FunkFMPEG: only 8-bit, non-interlaced PNGs are supported: $path';
        var channels = switch (colorType) {
            case 0: 1;
            case 2: 3;
            case 3: 1;
            case 4: 2;
            case 6: 4;
            default: 0;
        };
        if (channels == 0) throw 'FunkFMPEG: unsupported PNG color type $colorType: $path';
        if (colorType == 3 && (palette == null || palette.length < 3 || palette.length % 3 != 0)) throw 'FunkFMPEG: indexed PNG has no valid PLTE: $path';

        var rawSize:Float = width * 1.0 * channels * height;
        var rgbaSize:Float = width * 1.0 * height * 4;
        if (rawSize > 2147483000 || rgbaSize > 2147483000) throw 'FunkFMPEG: input PNG is too large to decode in memory: $path';
        var packed = Uncompress.run(idat.getBytes());
        var stride = width * channels;
        var expected:Float = (stride + 1.0) * height;
        if (expected > 2147483000 || packed.length < expected) throw 'FunkFMPEG: truncated or oversized PNG image data: $path';

        var raw = Bytes.alloc(stride * height);
        var src = 0;
        for (y in 0...height) {
            var filter = packed.get(src++);
            var row = y * stride;
            var prev = row - stride;
            // The filter switch is hoisted out of the per-byte loop (about 3x faster decoding).
            switch (filter) {
                case 0:
                    raw.blit(row, packed, src, stride);
                    src += stride;
                case 1:
                    for (x in 0...stride) {
                        var left = x >= channels ? raw.get(row + x - channels) : 0;
                        raw.set(row + x, (packed.get(src++) + left) & 255);
                    }
                case 2:
                    for (x in 0...stride) {
                        var up = y > 0 ? raw.get(prev + x) : 0;
                        raw.set(row + x, (packed.get(src++) + up) & 255);
                    }
                case 3:
                    for (x in 0...stride) {
                        var left = x >= channels ? raw.get(row + x - channels) : 0;
                        var up = y > 0 ? raw.get(prev + x) : 0;
                        raw.set(row + x, (packed.get(src++) + ((left + up) >> 1)) & 255);
                    }
                case 4:
                    for (x in 0...stride) {
                        var left = x >= channels ? raw.get(row + x - channels) : 0;
                        var up = y > 0 ? raw.get(prev + x) : 0;
                        var upLeft = (y > 0 && x >= channels) ? raw.get(prev + x - channels) : 0;
                        raw.set(row + x, (packed.get(src++) + paeth(left, up, upLeft)) & 255);
                    }
                default:
                    throw 'FunkFMPEG: unknown PNG filter $filter in $path';
            }
        }

        // 8-bit RGBA is already in the layout we need: no conversion pass, no extra copy.
        if (colorType == 6) return new PngImage(width, height, raw);

        var rgba = Bytes.alloc(Std.int(rgbaSize));
        var p = 0;
        for (i in 0...(width * height)) {
            var r = 0;
            var g = 0;
            var b = 0;
            var a = 255;
            switch (colorType) {
                case 0:
                    r = g = b = raw.get(i);
                    if (transparency != null && transparency.length >= 2) {
                        var transparentGray = (transparency.get(0) << 8) | transparency.get(1);
                        if (r == transparentGray) a = 0;
                    }
                case 2:
                    var qRgb = i * 3;
                    r = raw.get(qRgb); g = raw.get(qRgb + 1); b = raw.get(qRgb + 2);
                    if (transparency != null && transparency.length >= 6) {
                        var transparentR = (transparency.get(0) << 8) | transparency.get(1);
                        var transparentG = (transparency.get(2) << 8) | transparency.get(3);
                        var transparentB = (transparency.get(4) << 8) | transparency.get(5);
                        if (r == transparentR && g == transparentG && b == transparentB) a = 0;
                    }
                case 3:
                    var index = raw.get(i);
                    if (index * 3 + 2 >= palette.length) throw 'FunkFMPEG: indexed PNG references an invalid palette entry: $path';
                    r = palette.get(index * 3);
                    g = palette.get(index * 3 + 1);
                    b = palette.get(index * 3 + 2);
                    if (transparency != null && index < transparency.length) a = transparency.get(index);
                case 4:
                    var qGrayAlpha = i * 2;
                    r = g = b = raw.get(qGrayAlpha);
                    a = raw.get(qGrayAlpha + 1);
                case 6:
                    var qRgba = i * 4;
                    r = raw.get(qRgba); g = raw.get(qRgba + 1); b = raw.get(qRgba + 2); a = raw.get(qRgba + 3);
            }
            rgba.set(p++, r);
            rgba.set(p++, g);
            rgba.set(p++, b);
            rgba.set(p++, a);
        }
        return new PngImage(width, height, rgba);
    }

    /** Convenience writer for a contiguous row-major index buffer. */
    public static function writeIndexed(path:String, width:Int, height:Int, indices:Bytes, palette:Array<Array<Int>>, compression:Int):Void {
        var scanSize:Float = (width + 1.0) * height;
        if (scanSize > 2147483000 || indices.length < width * 1.0 * height) throw "FunkFMPEG: indexed PNG buffer is too large or incomplete";
        var scan = Bytes.alloc(Std.int(scanSize));
        for (y in 0...height) {
            var dst = y * (width + 1);
            scan.set(dst, 0);
            scan.blit(dst + 1, indices, y * width, width);
        }
        writeIndexedScanlines(path, width, height, scan, palette, compression);
    }

    /** Writes prebuilt PNG scanlines. This lets FunkFMPEG build the strip without a second full-size pixel buffer. */
    public static function writeIndexedScanlines(path:String, width:Int, height:Int, scanlines:Bytes, palette:Array<Array<Int>>, compression:Int):Void {
        if (width <= 0 || height <= 0 || palette == null || palette.length < 1 || palette.length > 256) throw "FunkFMPEG: invalid indexed PNG parameters";
        var expected:Float = (width + 1.0) * height;
        if (expected > 2147483000 || scanlines.length != expected) throw "FunkFMPEG: invalid PNG scanline buffer size";
        var compressed = Compress.run(scanlines, compression);

        var out:Output = File.write(path, true);
        try {
            out.writeBytes(Bytes.ofHex("89504e470d0a1a0a"), 0, 8);
            var ihdr = Bytes.alloc(13);
            putU32(ihdr, 0, width);
            putU32(ihdr, 4, height);
            ihdr.set(8, 8);  // bit depth
            ihdr.set(9, 3);  // indexed color
            ihdr.set(10, 0);
            ihdr.set(11, 0);
            ihdr.set(12, 0);
            writeChunk(out, "IHDR", ihdr);

            var plte = Bytes.alloc(palette.length * 3);
            var hasAlpha = false;
            var lastTransparent = -1;
            for (i in 0...palette.length) {
                var c = palette[i];
                plte.set(i * 3, c[0]);
                plte.set(i * 3 + 1, c[1]);
                plte.set(i * 3 + 2, c[2]);
                var alpha = c.length > 3 ? c[3] : 255;
                if (alpha < 255) { hasAlpha = true; lastTransparent = i; }
            }
            writeChunk(out, "PLTE", plte);

            if (hasAlpha) {
                var trns = Bytes.alloc(lastTransparent + 1);
                for (i in 0...trns.length) trns.set(i, palette[i].length > 3 ? palette[i][3] : 255);
                writeChunk(out, "tRNS", trns);
            }

            writeChunk(out, "IDAT", compressed);
            writeChunk(out, "IEND", Bytes.alloc(0));
            out.close();
        } catch (error:Dynamic) {
            out.close();
            throw error;
        }
    }

    static function writeChunk(out:Output, kind:String, data:Bytes):Void {
        var kindBytes = Bytes.ofString(kind);
        var len = Bytes.alloc(4);
        putU32(len, 0, data.length);
        out.writeBytes(len, 0, 4);
        out.writeBytes(kindBytes, 0, 4);
        out.writeBytes(data, 0, data.length);
        if (crcTable == null) crcTable = makeCrcTable();
        var crc = -1;
        for (i in 0...4) crc = crcByte(crc, kindBytes.get(i));
        for (i in 0...data.length) crc = crcByte(crc, data.get(i));
        var crcBytes = Bytes.alloc(4);
        putU32(crcBytes, 0, ~crc);
        out.writeBytes(crcBytes, 0, 4);
    }

    static var crcTable:Array<Int> = null;

    static function makeCrcTable():Array<Int> {
        var table:Array<Int> = [];
        for (n in 0...256) {
            var c = n;
            for (_ in 0...8) c = (c >>> 1) ^ ((c & 1) != 0 ? 0xEDB88320 : 0);
            table.push(c);
        }
        return table;
    }

    /** Table-driven CRC32 (8x faster than the bitwise loop on big strips). */
    static inline function crcByte(crc:Int, value:Int):Int {
        return crcTable[(crc ^ value) & 255] ^ (crc >>> 8);
    }

    static inline function readU32(b:Bytes, p:Int):Int {
        return (b.get(p) << 24) | (b.get(p + 1) << 16) | (b.get(p + 2) << 8) | b.get(p + 3);
    }

    static function putU32(b:Bytes, p:Int, v:Int):Void {
        b.set(p, (v >>> 24) & 255);
        b.set(p + 1, (v >>> 16) & 255);
        b.set(p + 2, (v >>> 8) & 255);
        b.set(p + 3, v & 255);
    }

    static function paeth(a:Int, b:Int, c:Int):Int {
        var p = a + b - c;
        var pa = p - a; if (pa < 0) pa = -pa;
        var pb = p - b; if (pb < 0) pb = -pb;
        var pc = p - c; if (pc < 0) pc = -pc;
        return pa <= pb && pa <= pc ? a : (pb <= pc ? b : c);
    }
}
