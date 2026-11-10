import funkfmpeg.FunkFMPEG;
import funkfmpeg.TapeOptions;

class Basic {
    static function main() {
        var frames = [for (i in 1...415) "frames/frame_" + StringTools.lpad(Std.string(i), "0", 6) + ".png"];
        var options = new TapeOptions();
        options.scaleDivisor = 0;       // 0 = AUTO: biggest frame allowed
        options.maxWidth = 16384;       // your engine/GPU texture limit
        options.colors = 256;
        options.compression = 9;
        options.keepAlpha = false;     // true keeps source transparency
        options.palettePath = "palette.png";
        options.paletteTextPath = "palette.txt";
        options.onProgress = function(percent) Sys.println(percent + "%");
        var result = FunkFMPEG.create(frames, "filmstrip.png", options);
        Sys.println('Created one horizontal ${result.width}x${result.height} strip from ${result.frameCount} frames');
    }
}
