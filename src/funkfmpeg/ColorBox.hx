package funkfmpeg;

class ColorBox {
    public var colors:Array<ColorBin>;
    public var population:Int = 0;
    public var rangeR:Int = 0;
    public var rangeG:Int = 0;
    public var rangeB:Int = 0;
    public var rangeA:Int = 0;

    public function new(colors:Array<ColorBin>) {
        this.colors = colors;
        refresh();
    }

    public function refresh():Void {
        population = 0;
        var minR = 255, minG = 255, minB = 255, minA = 255;
        var maxR = 0, maxG = 0, maxB = 0, maxA = 0;
        for (c in colors) {
            population += c.count;
            if (c.r < minR) minR = c.r;
            if (c.r > maxR) maxR = c.r;
            if (c.g < minG) minG = c.g;
            if (c.g > maxG) maxG = c.g;
            if (c.b < minB) minB = c.b;
            if (c.b > maxB) maxB = c.b;
            if (c.a < minA) minA = c.a;
            if (c.a > maxA) maxA = c.a;
        }
        rangeR = maxR - minR;
        rangeG = maxG - minG;
        rangeB = maxB - minB;
        rangeA = maxA - minA;
    }

    public function longestChannel(keepAlpha:Bool):Int {
        var channel = 0;
        var range = rangeR;
        if (rangeG > range) { range = rangeG; channel = 1; }
        if (rangeB > range) { range = rangeB; channel = 2; }
        if (keepAlpha && rangeA > range) channel = 3;
        return channel;
    }

    public function split(keepAlpha:Bool):Null<ColorBox> {
        if (colors.length < 2) return null;
        var channel = longestChannel(keepAlpha);
        colors.sort(function(a, b) {
            return switch (channel) {
                case 0: a.r - b.r;
                case 1: a.g - b.g;
                case 2: a.b - b.b;
                default: a.a - b.a;
            };
        });
        var half:Float = population / 2;
        var sum = 0;
        var at = 0;
        while (at < colors.length - 1 && sum < half) {
            sum += colors[at].count;
            at++;
        }
        var left = colors.slice(0, at);
        var right = colors.slice(at);
        if (left.length == 0 || right.length == 0) return null;
        colors = left;
        refresh();
        return new ColorBox(right);
    }

    public function average():Array<Int> {
        var r:Float = 0, g:Float = 0, b:Float = 0, a:Float = 0, total:Float = 0;
        for (c in colors) {
            r += c.r * c.count;
            g += c.g * c.count;
            b += c.b * c.count;
            a += c.a * c.count;
            total += c.count;
        }
        if (total == 0) return [0, 0, 0, 255];
        return [Std.int(r / total + 0.5), Std.int(g / total + 0.5), Std.int(b / total + 0.5), Std.int(a / total + 0.5)];
    }
}
