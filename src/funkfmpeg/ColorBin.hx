package funkfmpeg;

class ColorBin {
    public var r:Int;
    public var g:Int;
    public var b:Int;
    public var a:Int;
    public var count:Int;
    /** Histogram cell this bin came from (see PaletteBuilder.key). */
    public var key:Int;

    public function new(r:Int, g:Int, b:Int, a:Int, count:Int, key:Int = 0) {
        this.r = r;
        this.g = g;
        this.b = b;
        this.a = a;
        this.count = count;
        this.key = key;
    }
}
