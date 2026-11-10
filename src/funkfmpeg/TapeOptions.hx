package funkfmpeg;

class TapeOptions {
    /**
     * Scale divisor. 3 turns 1920x1080 into 640x360.
     * 0 (default) = AUTO: use the largest frame size that fits every limit below
     * (never upscales past the source size).
     */
    public var scaleDivisor:Float = 0;
    /** If > 0, uses this output frame width and preserves the aspect ratio. Overrides scaleDivisor. */
    public var frameWidth:Int = 0;
    /** Max width in pixels of the final strip (0 = no limit besides the Haxe buffer limit). Used by AUTO. */
    public var maxWidth:Int = 0;
    /** Max height in pixels of the final strip (0 = no limit). Used by AUTO. */
    public var maxHeight:Int = 0;
    /**
     * Max total pixels of the strip (width * height). Default 84,800,000 = the size of a 264920x320 strip,
     * a strip size known to work. Set 0 to remove it (then only the Haxe buffer limit applies). Used by AUTO.
     */
    public var maxPixels:Float = 84800000;
    /** Max size in bytes of the raw strip buffer, (width + 1) * height (0 = Haxe Bytes limit, ~2 GB). Used by AUTO. */
    public var maxBytes:Float = 0;
    /** Maximum number of colors in the global palette (2..256). */
    public var colors:Int = 256;
    /** PNG zlib compression level (0..9). */
    public var compression:Int = 9;
    /** Palette refinement passes (k-means on the median-cut palette). 0 disables it. */
    public var refine:Int = 4;
    /** Preserve source alpha in the indexed PNG. False composites frames over background. */
    public var keepAlpha:Bool = false;
    /** RGB background used when keepAlpha is false. */
    public var background:Int = 0x000000;
    /** Optional path to write the global palette as a PNG. */
    public var palettePath:Null<String> = null;
    /** Optional path to write palette entries as R,G,B,A lines. */
    public var paletteTextPath:Null<String> = null;
    /** Optional progress callback receiving values from 0 to 100. */
    public var onProgress:Null<Int->Void> = null;

    public function new() {}
}
