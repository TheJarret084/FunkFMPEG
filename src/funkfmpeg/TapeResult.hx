package funkfmpeg;

class TapeResult {
    public var width:Int;
    public var height:Int;
    public var frameWidth:Int;
    public var frameHeight:Int;
    public var frameCount:Int;
    public var paletteSize:Int;
    public var hasAlpha:Bool;

    public function new(width:Int, height:Int, frameWidth:Int, frameHeight:Int, frameCount:Int, paletteSize:Int, hasAlpha:Bool) {
        this.width = width;
        this.height = height;
        this.frameWidth = frameWidth;
        this.frameHeight = frameHeight;
        this.frameCount = frameCount;
        this.paletteSize = paletteSize;
        this.hasAlpha = hasAlpha;
    }
}
