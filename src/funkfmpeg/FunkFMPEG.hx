package funkfmpeg;

/** Public entry point for the FunkFMPEG Haxe library. */
class FunkFMPEG {
    public static inline var VERSION:String = "1.1.0";

    public static function create(frames:Array<String>, outputPath:String, ?options:TapeOptions):TapeResult {
        return Tape.create(frames, outputPath, options);
    }
}
