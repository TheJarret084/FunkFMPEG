package funkfmpeg;

typedef SheetPage = {
    /** File name inside the output folder (not the full path). */
    var file:String;
    var width:Int;
    var height:Int;
}

typedef SheetSlot = {
    /** Page index (see `SheetResult.pages`). */
    var page:Int;
    /** Top-left corner of the frame inside the page. */
    var x:Int;
    var y:Int;
    /** Index of the unique cell this frame uses (duplicated frames share it). */
    var unique:Int;
}

class SheetResult {
    public var pages:Array<SheetPage>;
    /** One entry per INPUT frame, in the same order. Duplicated frames point to the same cell. */
    public var slots:Array<SheetSlot>;
    public var frameWidth:Int;
    public var frameHeight:Int;
    public var sourceWidth:Int;
    public var sourceHeight:Int;
    public var frameCount:Int;
    public var uniqueCount:Int;
    public var paletteSize:Int;
    public var hasAlpha:Bool;
    public var padding:Int;

    public function new(pages:Array<SheetPage>, slots:Array<SheetSlot>, frameWidth:Int, frameHeight:Int, sourceWidth:Int, sourceHeight:Int, uniqueCount:Int, paletteSize:Int, hasAlpha:Bool, padding:Int) {
        this.pages = pages;
        this.slots = slots;
        this.frameWidth = frameWidth;
        this.frameHeight = frameHeight;
        this.sourceWidth = sourceWidth;
        this.sourceHeight = sourceHeight;
        this.frameCount = slots.length;
        this.uniqueCount = uniqueCount;
        this.paletteSize = paletteSize;
        this.hasAlpha = hasAlpha;
        this.padding = padding;
    }
}
