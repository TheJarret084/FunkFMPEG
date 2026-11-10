package funkfmpeg;

import haxe.io.Bytes;

class PaletteResult {
    /** Palette entries as [r, g, b, a]. With keepAlpha they are sorted by alpha (transparent first). */
    public var colors:Array<Array<Int>>;
    /** Histogram cell (PaletteBuilder.key) -> palette index. Exact for every cell that appeared in the frames. */
    public var lookup:Bytes;

    public function new(colors:Array<Array<Int>>, lookup:Bytes) {
        this.colors = colors;
        this.lookup = lookup;
    }
}
