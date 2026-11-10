package funkfmpeg.cli;

import funkfmpeg.FunkFMPEG;
import funkfmpeg.TapeOptions;
import sys.FileSystem;

class Main {
    static function main():Void {
        var args = Sys.args();
        if (args.length < 2) {
            Sys.println("Usage: haxe -cp src --run funkfmpeg.cli.Main <frames-folder> <output.png> [scale-divisor|auto] [colors] [keep-alpha] [max-width] [max-height]");
            Sys.println("Example (largest possible frames, strip max 16384 wide): haxe -cp src --run funkfmpeg.cli.Main frames filmstrip.png auto 256 false 16384");
            return;
        }
        var folder = args[0];
        var output = args[1];
        var divisor:Float = 0; // 0 = auto: biggest frame allowed
        var colors:Int = 256;
        var keepAlpha = false;
        if (args.length > 2) {
            if (args[2].toLowerCase() == "auto") {
                divisor = 0;
            } else {
                var parsed = Std.parseFloat(args[2]);
                if (Math.isNaN(parsed) || parsed < 0) throw "FunkFMPEG: scale-divisor must be 'auto' or a number greater than zero";
                divisor = parsed;
            }
        }
        if (args.length > 3) {
            var parsed = Std.parseInt(args[3]);
            if (parsed == null || parsed < 2 || parsed > 256) throw "FunkFMPEG: colors must be between 2 and 256";
            colors = parsed;
        }
        if (args.length > 4) {
            var value = args[4].toLowerCase();
            if (value != "true" && value != "false" && value != "1" && value != "0") throw "FunkFMPEG: keep-alpha must be true or false";
            keepAlpha = value == "true" || value == "1";
        }
        var maxWidth = 0;
        var maxHeight = 0;
        if (args.length > 5) {
            var parsed = Std.parseInt(args[5]);
            if (parsed == null || parsed < 0) throw "FunkFMPEG: max-width must be 0 (no limit) or a positive number";
            maxWidth = parsed;
        }
        if (args.length > 6) {
            var parsed = Std.parseInt(args[6]);
            if (parsed == null || parsed < 0) throw "FunkFMPEG: max-height must be 0 (no limit) or a positive number";
            maxHeight = parsed;
        }
        if (args.length > 7) throw "FunkFMPEG: too many arguments";
        if (!FileSystem.exists(folder) || !FileSystem.isDirectory(folder)) throw 'FunkFMPEG: input folder not found: $folder';

        var files = FileSystem.readDirectory(folder);
        files = files.filter(function(name) return ~/\.png$/i.match(name));
        files.sort(function(a, b) return Reflect.compare(a.toLowerCase(), b.toLowerCase()));
        if (files.length == 0) throw 'FunkFMPEG: no PNG frames found in $folder';
        var paths = [for (name in files) folder + "/" + name];

        var options = new TapeOptions();
        options.scaleDivisor = divisor;
        options.colors = colors;
        options.keepAlpha = keepAlpha;
        options.maxWidth = maxWidth;
        options.maxHeight = maxHeight;
        options.palettePath = "palette.png";
        options.paletteTextPath = "palette.txt";
        options.onProgress = function(value) Sys.print("\rFunkFMPEG: " + value + "%   ");
        var result = FunkFMPEG.create(paths, output, options);
        Sys.println('\nDone: ${result.width}x${result.height} (frame ${result.frameWidth}x${result.frameHeight}) | ${result.frameCount} frames | ${result.paletteSize} colors | alpha: ${result.hasAlpha}');
    }
}
