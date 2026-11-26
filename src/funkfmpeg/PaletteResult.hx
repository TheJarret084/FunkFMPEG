package funkfmpeg;

import haxe.ds.Vector;
import haxe.io.Bytes;

class PaletteResult {
    /** Palette entries as [r, g, b, a]. With keepAlpha they are sorted by alpha (transparent first). */
    public var colors:Array<Array<Int>>;
    /** Histogram cell (PaletteBuilder.key) -> palette index. Exact for every cell that appeared in the frames. */
    public var lookup:Bytes;

    var known:Null<Bytes>;
    var pr:Null<Vector<Float>>;
    var pg:Null<Vector<Float>>;
    var pb:Null<Vector<Float>>;
    var pa:Null<Vector<Float>>;
    var keepAlpha:Bool;

    public function new(colors:Array<Array<Int>>, lookup:Bytes, ?known:Bytes, ?pr:Vector<Float>, ?pg:Vector<Float>, ?pb:Vector<Float>, ?pa:Vector<Float>, keepAlpha:Bool = false) {
        this.colors = colors;
        this.lookup = lookup;
        this.known = known;
        this.pr = pr;
        this.pg = pg;
        this.pb = pb;
        this.pa = pa;
        this.keepAlpha = keepAlpha;
    }

    /**
     * Palette index for one pixel. Same as `lookup.get(PaletteBuilder.key(...))` for cells the palette was built from,
     * but it also works for cells that never showed up while building (for example when the palette was built from
     * a sample of the frames): the nearest color is computed once and cached.
     */
    public inline function index(r:Int, g:Int, b:Int, a:Int):Int {
        var k = PaletteBuilder.key(r, g, b, a, keepAlpha);
        if (known == null || known.get(k) != 0) return lookup.get(k);
        return fill(k, r, g, b, a);
    }

    function fill(k:Int, r:Int, g:Int, b:Int, a:Int):Int {
        var best = PaletteBuilder.nearest(r, g, b, a, pr, pg, pb, pa, colors.length, keepAlpha);
        lookup.set(k, best);
        known.set(k, 1);
        return best;
    }
}
