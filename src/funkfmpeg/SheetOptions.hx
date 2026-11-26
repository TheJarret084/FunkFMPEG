package funkfmpeg;

/**
 * Options for `FunkFMPEG.createSheet`: frames packed in a grid of pages (spritesheet) instead of one endless strip.
 * It extends TapeOptions, so colors / compression / refine / keepAlpha / background / scaleDivisor / frameWidth /
 * palettePath / paletteTextPath / onProgress work the same way.
 */
class SheetOptions extends TapeOptions {
    /** Max width and height of every page PNG. 4096 is safe on almost every GPU (including phones). */
    public var maxPage:Int = 4096;
    /**
     * Max number of pages (0 = no limit). In AUTO size mode the frames get smaller until everything fits in this many pages.
     * With 0, AUTO keeps the source size (only shrinking it when one frame would not fit in a page).
     */
    public var maxPages:Int = 0;
    /** Gap in pixels between frames (2 = 1px of border repeat per side). Half of the gap repeats the frame border, so bilinear filtering never bleeds a neighbor. */
    public var padding:Int = 2;
    /** Identical frames (same pixels) share one cell. A loop with static parts costs only its unique frames. */
    public var dedup:Bool = true;
    /** Frames used to build the palette (0 = all). Evenly spaced, always the first and the last. Faster with long videos, same look. */
    public var paletteSample:Int = 64;
    /** Page file names: `<baseName>.png`, `<baseName>_p1.png`, `<baseName>_p2.png`... */
    public var baseName:String = "sprite";
    /** Optional path to write the layout (pages, frame size and the page/x/y of every frame) as JSON. */
    public var layoutPath:Null<String> = null;

    public function new() {
        super();
    }
}
