package funkfmpeg;

import funkfmpeg.AudioTools.AudioInfo;
import funkfmpeg.VideoFrames.VideoInfo;
import haxe.io.Path;
import sys.FileSystem;

/**
 * Punto de entrada unico de FunkFMPEG: imagen (RGB -> indexed), video y audio.
 * Video/audio necesitan el ndll con FFmpeg (Windows/Linux/Android 64).
 */
class FunkFMPEG {
    public static inline var VERSION:String = "1.4.10";

    // ------------------------------------------------------------------ imagen

    public static function create(frames:Array<String>, outputPath:String, ?options:TapeOptions):TapeResult {
        return Tape.create(frames, outputPath, options);
    }

    /**
     * Grid spritesheet split in pages (each <= options.maxPage), identical frames stored once.
     * Writes `<outDir>/<baseName>.png`, `<baseName>_p1.png`... and returns where every frame is.
     */
    public static function createSheet(frames:Array<String>, outDir:String, ?options:SheetOptions):SheetResult {
        return Sheet.create(frames, outDir, options);
    }

    /** PNG RGB/RGBA -> PNG indexado (paleta de `colors`), mismo tamano. */
    public static function optimizePng(src:String, dst:String, colors:Int = 256, keepAlpha:Bool = true, compression:Int = 9):TapeResult {
        var o = new TapeOptions();
        o.colors = colors;
        o.keepAlpha = keepAlpha;
        o.compression = compression;
        return Tape.create([src], dst, o);
    }

    /** Optimiza todos los .png de una carpeta hacia otra. Devuelve las rutas escritas. */
    public static function optimizeFolder(srcDir:String, dstDir:String, colors:Int = 256, keepAlpha:Bool = true, compression:Int = 9):Array<String> {
        if (!FileSystem.exists(dstDir)) FileSystem.createDirectory(dstDir);
        var out:Array<String> = [];
        var names = FileSystem.readDirectory(srcDir).filter(function(n) return ~/\.png$/i.match(n));
        names.sort(function(a, b) return Reflect.compare(a.toLowerCase(), b.toLowerCase()));
        for (n in names) {
            var dst = Path.join([dstDir, n]);
            optimizePng(Path.join([srcDir, n]), dst, colors, keepAlpha, compression);
            out.push(dst);
        }
        return out;
    }

    // ------------------------------------------------------------------ video

    public static function videoInfo(path:String):Null<VideoInfo> {
        return VideoFrames.probe(path);
    }

    /**
     * Video -> frames PNG (`f000001.png`...) en outDir. Bloquea hasta terminar (usa un hilo si no quieres congelar el juego).
     * fps = 0 usa el del video; width/height = 0 usan el original (si das solo uno se mantiene la proporcion).
     * maxFrames = 0 sin limite; exactFrames = N reparte N frames en toda la duracion. Devuelve las rutas de los frames.
     */
    public static function videoToFrames(path:String, outDir:String, fps:Float = 0, width:Int = 0, height:Int = 0, maxFrames:Int = 0, ?onProgress:Int->Void, exactFrames:Int = 0):Array<String> {
        var info = VideoFrames.probe(path);
        if (info == null) throw "FunkFMPEG: no se pudo leer el video: " + path;
        var useFps:Float = fps > 0 ? fps : info.fps;
        if (exactFrames > 0) {
            if (info.seconds <= 0) throw "FunkFMPEG: el video no reporta duracion, usa fps/maxFrames";
            useFps = exactFrames / info.seconds; // N frames repartidos en toda la duracion
            maxFrames = exactFrames;
        }
        var size = resolveSize(info, width, height);
        var total:Int = Math.ceil(info.seconds * useFps) + 1;
        if (info.seconds <= 0) total = 1000000;
        if (maxFrames > 0 && maxFrames < total) total = maxFrames;
        if (!VideoFrames.start(path, outDir, Math.round(useFps * 1000), size[0], size[1], total))
            throw "FunkFMPEG: " + VideoFrames.error();
        while (VideoFrames.state() == VideoFrames.RUNNING) {
            Sys.sleep(0.02);
            if (onProgress != null) onProgress(VideoFrames.progress());
        }
        if (VideoFrames.state() != VideoFrames.DONE) throw "FunkFMPEG: " + VideoFrames.error();
        var n = VideoFrames.progress();
        return [for (i in 1...n + 1) outDir + "/f" + StringTools.lpad(Std.string(i), "0", 6) + ".png"];
    }

    /** Video -> spritesheet indexado paginado (extrae, indexa y borra los temporales). frames = N como en videoToStrip. */
    public static function videoToSheet(path:String, outDir:String, ?options:SheetOptions, frames:Int = 0, fps:Float = 0, width:Int = 0, height:Int = 0, ?onProgress:Int->Void):SheetResult {
        if (!FileSystem.exists(outDir)) FileSystem.createDirectory(outDir);
        var tmp = Path.join([outDir, "_frames"]);
        var files = videoToFrames(path, tmp, fps, width, height, 0, onProgress, frames);
        if (options == null) options = new SheetOptions();
        if (options.layoutPath == null) options.layoutPath = Path.join([outDir, "layout.json"]);
        try {
            var result = createSheet(files, outDir, options);
            removeDir(tmp);
            return result;
        } catch (e:Dynamic) {
            removeDir(tmp);
            throw e;
        }
    }

    /**
     * Video -> tira horizontal indexada: una sola fila de celdas (un solo PNG), una celda por frame.
     * frames = N toma exactamente N frames repartidos en TODA la duracion; 0 usa fps (o el del video).
     */
    public static function videoToStrip(path:String, outPng:String, ?options:TapeOptions, frames:Int = 0, fps:Float = 0, width:Int = 0, height:Int = 0, ?onProgress:Int->Void):TapeResult {
        var dir = Path.directory(outPng);
        if (dir == "") dir = ".";
        var tmp = Path.join([dir, "_frames_tmp"]);
        var files = videoToFrames(path, tmp, fps, width, height, 0, onProgress, frames);
        try {
            var result = create(files, outPng, options);
            removeDir(tmp);
            return result;
        } catch (e:Dynamic) {
            removeDir(tmp);
            throw e;
        }
    }

    // ------------------------------------------------------------------ audio

    public static function audioInfo(path:String):Null<AudioInfo> {
        return AudioTools.probe(path);
    }

    /**
     * Audio (mp3/ogg/opus/flac/aac/wav) o el audio de un video -> OGG Vorbis (unica salida de audio). Bloqueante.
     * quality 0..10 (VBR, 5 ~ 160 kbps). sampleRate = 0 mantiene el original; channels = 0 mantiene mono/stereo.
     */
    public static function audioToOgg(src:String, dstOgg:String, quality:Int = 5, sampleRate:Int = 0, channels:Int = 0):Void {
        if (!AudioTools.toOgg(src, dstOgg, sampleRate, channels, quality)) throw "FunkFMPEG: " + AudioTools.error();
    }

    // ------------------------------------------------------------------ interno

    static function resolveSize(info:VideoInfo, width:Int, height:Int):Array<Int> {
        var w = width;
        var h = height;
        if (w <= 0 && h <= 0) { w = info.w; h = info.h; }
        else if (w <= 0) w = Math.round(info.w * h / info.h);
        else if (h <= 0) h = Math.round(info.h * w / info.w);
        return [evenAtLeast2(w), evenAtLeast2(h)];
    }

    static inline function evenAtLeast2(v:Int):Int {
        var e = v - (v % 2);
        return e < 2 ? 2 : e;
    }

    static function removeDir(dir:String):Void {
        try {
            if (!FileSystem.exists(dir)) return;
            for (n in FileSystem.readDirectory(dir)) FileSystem.deleteFile(Path.join([dir, n]));
            FileSystem.deleteDirectory(dir);
        } catch (_:Dynamic) {}
    }
}
