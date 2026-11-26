package funkfmpeg;

import haxe.Int32;
import haxe.Json;
import haxe.io.Bytes;
import haxe.io.Path;
import funkfmpeg.SheetResult.SheetPage;
import funkfmpeg.SheetResult.SheetSlot;
import sys.FileSystem;
import sys.io.File;

/**
 * Packs an ordered frame list into a grid spritesheet split in pages (each page <= maxPage x maxPage).
 * Better than a strip for a game: no 200000px wide texture, identical frames are stored once, and every page
 * is a normal GPU-friendly indexed PNG that shares one global palette.
 */
class Sheet {
    public static function create(frames:Array<String>, outDir:String, ?options:SheetOptions):SheetResult {
        if (options == null) options = new SheetOptions();
        if (frames == null || frames.length == 0) throw "FunkFMPEG: no input frames";
        if (outDir == null || outDir.length == 0) throw "FunkFMPEG: output folder is empty";
        if (options.compression < 0 || options.compression > 9) throw "FunkFMPEG: compression must be between 0 and 9";
        if (options.colors < 2 || options.colors > 256) throw "FunkFMPEG: colors must be between 2 and 256";
        if (options.maxPage < 16) throw "FunkFMPEG: maxPage is too small";
        var pad = options.padding < 0 ? 0 : options.padding;
        var report = function(value:Float) {
            if (options.onProgress != null) options.onProgress(Std.int(value));
        };
        if (!FileSystem.exists(outDir)) FileSystem.createDirectory(outDir);
        report(0);

        // 1) Hash every frame: which ones are the same picture.
        var first = PngImage.read(frames[0]);
        var sw = first.width;
        var sh = first.height;
        var uniqueOf:Array<Int> = [];
        var uniquePaths:Array<String> = [];
        var seen = new Map<String, Int>();
        for (i in 0...frames.length) {
            var image = i == 0 ? first : PngImage.read(frames[i]);
            if (image.width != sw || image.height != sh) {
                throw 'FunkFMPEG: frame dimensions differ. Expected ${sw}x${sh}, got ${image.width}x${image.height}: ${frames[i]}';
            }
            var index:Null<Int> = null;
            var key:Null<String> = null;
            if (options.dedup) {
                key = hashFrame(image.rgba);
                index = seen.get(key);
            }
            if (index == null) {
                index = uniquePaths.length;
                uniquePaths.push(frames[i]);
                if (key != null) seen.set(key, index);
            }
            uniqueOf.push(index);
            report((i + 1) * 20 / frames.length);
        }
        first = null;
        var unique = uniquePaths.length;

        // 2) Frame size and grid.
        var size = frameSize(sw, sh, unique, options, pad);
        var fw = size[0];
        var fh = size[1];
        var cellW = fw + pad;
        var cellH = fh + pad;
        var maxCols = Std.int((options.maxPage - pad) / cellW);
        var maxRows = Std.int((options.maxPage - pad) / cellH);
        if (maxCols < 1 || maxRows < 1) throw 'FunkFMPEG: a ${fw}x${fh} frame does not fit in a ${options.maxPage}px page';
        var perPage = maxCols * maxRows;
        var pageCount = Std.int((unique + perPage - 1) / perPage);
        if (options.maxPages > 0 && pageCount > options.maxPages) {
            throw 'FunkFMPEG: $unique unique frames of ${fw}x${fh} need $pageCount pages, the limit is ${options.maxPages}. Use scaleDivisor = 0 (auto) or raise maxPages.';
        }

        // 3) One palette for all the pages (built from a sample of the unique frames).
        var paletteFrames = sampleOf(uniquePaths, options.paletteSample);
        var paletteOptions = new TapeOptions();
        paletteOptions.colors = options.colors;
        paletteOptions.refine = options.refine;
        paletteOptions.keepAlpha = options.keepAlpha;
        paletteOptions.background = options.background;
        paletteOptions.compression = options.compression;
        paletteOptions.palettePath = options.palettePath;
        paletteOptions.paletteTextPath = options.paletteTextPath;
        paletteOptions.onProgress = function(value:Int) report(20 + value * 25 / 42);
        var built = PaletteBuilder.build(paletteFrames, fw, fh, sw, sh, paletteOptions);
        var palette = built.colors;
        var keepAlpha = options.keepAlpha;

        // 4) Write the pages, one at a time (only one page buffer lives in memory).
        var pages:Array<SheetPage> = [];
        var cells:Array<SheetSlot> = [];
        var next = 0;
        for (page in 0...pageCount) {
            var inPage = Std.int(Math.min(perPage, unique - page * perPage));
            var cols = page < pageCount - 1 ? maxCols : bestColumns(inPage, maxCols, cellW, cellH);
            var rows = Std.int((inPage + cols - 1) / cols);
            if (page < pageCount - 1) rows = maxRows;
            var pageW = pad + cols * cellW;
            var pageH = pad + rows * cellH;
            var stride = pageW + 1;
            var scan = Bytes.alloc(stride * pageH);
            // Empty space is index 0 (transparent when keepAlpha: the palette is sorted by alpha).
            for (y in 0...pageH) scan.set(y * stride, 0);

            for (c in 0...inPage) {
                var image = PngImage.read(uniquePaths[next]);
                var pixels = FrameScale.resize(image, fw, fh, options.background, keepAlpha);
                var x0 = pad + (c % cols) * cellW;
                var y0 = pad + Std.int(c / cols) * cellH;
                var p = 0;
                for (y in 0...fh) {
                    var dst = (y0 + y) * stride + 1 + x0;
                    for (x in 0...fw) {
                        scan.set(dst + x, built.index(pixels.get(p), pixels.get(p + 1), pixels.get(p + 2), pixels.get(p + 3)));
                        p += 4;
                    }
                }
                extrude(scan, stride, x0, y0, fw, fh, pad >> 1);
                cells.push({page: page, x: x0, y: y0, unique: next});
                next++;
                report(45 + next * 54 / unique);
            }

            var file = pageFile(options.baseName, page);
            PngImage.writeIndexedScanlines(Path.join([outDir, file]), pageW, pageH, scan, palette, options.compression);
            pages.push({file: file, width: pageW, height: pageH});
        }

        var slots:Array<SheetSlot> = [for (u in uniqueOf) cells[u]];
        var result = new SheetResult(pages, slots, fw, fh, sw, sh, unique, palette.length, keepAlpha, pad);
        if (options.layoutPath != null) File.saveContent(options.layoutPath, layoutJson(result));
        report(100);
        return result;
    }

    public static inline function pageFile(baseName:String, index:Int):String {
        return index == 0 ? baseName + ".png" : baseName + "_p" + index + ".png";
    }

    /** Layout as JSON: {"frameWidth","frameHeight","padding","pages":[{file,width,height}],"frames":[[page,x,y,unique],...]}. */
    public static function layoutJson(result:SheetResult):String {
        return Json.stringify({
            frameWidth: result.frameWidth,
            frameHeight: result.frameHeight,
            sourceWidth: result.sourceWidth,
            sourceHeight: result.sourceHeight,
            padding: result.padding,
            unique: result.uniqueCount,
            pages: result.pages,
            frames: [for (s in result.slots) [s.page, s.x, s.y, s.unique]]
        });
    }

    /** Frame size: fixed (frameWidth / scaleDivisor) or AUTO = the biggest one whose unique frames fit in maxPages pages. */
    public static function frameSize(sw:Int, sh:Int, unique:Int, options:SheetOptions, pad:Int):Array<Int> {
        if (options.frameWidth > 0) {
            var w = options.frameWidth;
            return [w, FrameScale.heightFor(sw, sh, w)];
        }
        if (options.scaleDivisor > 0) {
            var w = Std.int(Math.max(1, Math.floor(sw / options.scaleDivisor)));
            return [w, FrameScale.heightFor(sw, sh, w)];
        }
        var allowed = function(fw:Int):Bool {
            var fh = FrameScale.heightFor(sw, sh, fw);
            var cols = Std.int((options.maxPage - pad) / (fw + pad));
            var rows = Std.int((options.maxPage - pad) / (fh + pad));
            if (cols < 1 || rows < 1) return false;
            if (options.maxPages <= 0) return true;
            return Std.int((unique + cols * rows - 1) / (cols * rows)) <= options.maxPages;
        };
        if (!allowed(1)) throw "FunkFMPEG: the frames cannot fit inside the given maxPage/maxPages limits";
        var lo = 1;
        var hi = sw;
        while (lo < hi) {
            var mid = lo + ((hi - lo + 1) >> 1);
            if (allowed(mid)) lo = mid; else hi = mid - 1;
        }
        return [lo, FrameScale.heightFor(sw, sh, lo)];
    }

    /** Columns for a page of `n` cells that is as square as possible (smaller texture than one long row). */
    static function bestColumns(n:Int, maxCols:Int, cellW:Int, cellH:Int):Int {
        var cols = Std.int(Math.ceil(Math.sqrt(n * cellH / cellW)));
        if (cols < 1) cols = 1;
        if (cols > maxCols) cols = maxCols;
        if (cols > n) cols = n;
        return cols;
    }

    static function sampleOf(paths:Array<String>, wanted:Int):Array<String> {
        if (wanted <= 0 || paths.length <= wanted) return paths;
        if (wanted == 1) return [paths[0]];
        var out:Array<String> = [];
        for (i in 0...wanted) out.push(paths[Std.int(Math.round(i * (paths.length - 1) / (wanted - 1)))]);
        return out;
    }

    /** Repeats the border of the frame into the padding (n pixels per side; padding / 2, so two neighbors never overwrite each other) so filtering at the edges never mixes in a neighbor frame. */
    static function extrude(scan:Bytes, stride:Int, x0:Int, y0:Int, fw:Int, fh:Int, n:Int):Void {
        if (n <= 0) return;
        for (y in 0...fh) {
            var row = (y0 + y) * stride + 1;
            var left = scan.get(row + x0);
            var right = scan.get(row + x0 + fw - 1);
            for (k in 1...n + 1) {
                scan.set(row + x0 - k, left);
                scan.set(row + x0 + fw - 1 + k, right);
            }
        }
        var width = fw + n * 2;
        var top = (y0) * stride + 1 + x0 - n;
        var bottom = (y0 + fh - 1) * stride + 1 + x0 - n;
        for (k in 1...n + 1) {
            scan.blit((y0 - k) * stride + 1 + x0 - n, scan, top, width);
            scan.blit((y0 + fh - 1 + k) * stride + 1 + x0 - n, scan, bottom, width);
        }
    }

    /** Two 32-bit hashes + length of the pixels: equal pictures give the same key. Reads 4 bytes at a time. */
    static function hashFrame(rgba:Bytes):String {
        var h1:Int32 = 0x811C9DC5;
        var h2:Int32 = 0x1B873593;
        var n = rgba.length & ~3;
        var p = 0;
        while (p < n) {
            var w:Int32 = rgba.getInt32(p);
            h1 = (h1 ^ w) * 16777619;
            h2 = (h2 + w) * 0x85EBCA6B;
            h2 = h2 ^ (h2 >>> 13);
            p += 4;
        }
        var a:Int = h1;
        var b:Int = h2;
        return a + ":" + b + ":" + rgba.length;
    }
}
