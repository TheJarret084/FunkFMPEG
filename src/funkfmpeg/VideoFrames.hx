package funkfmpeg;

#if cpp
import cpp.Prime;
#end

/**
 * Extraccion de frames de video para FunkFMPEG.
 *
 * cpp (Windows/Linux/Android 64): ndll nativo C++ con FFmpeg (libavformat/libavcodec/libswscale) enlazado estatico.
 */
class VideoFrames
{
	public static inline var IDLE:Int = 0;
	public static inline var RUNNING:Int = 1;
	public static inline var DONE:Int = 2;
	public static inline var FAILED:Int = 3;
	public static inline var CANCELLED:Int = 4;

	#if cpp
	static var _probe:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_probe", "ss");
	static var _start:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_start", "ssiiiii");
	static var _progress:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_progress", "i");
	static var _state:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_state", "i");
	static var _error:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_error", "s");
	static var _cancel:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_cancel", "v");

	public static function probe(path:String):Null<VideoInfo>
	{
		try { return parseProbe(_probe(path)); }
		catch (_:Dynamic) {}
		return null;
	}

	public static function start(path:String, outDir:String, fpsMilli:Int, width:Int, height:Int, count:Int):Bool
	{
		try { return _start(path, outDir, fpsMilli, width, height, count) == 1; }
		catch (_:Dynamic) {}
		return false;
	}

	public static function progress():Int { try { return _progress(); } catch (_:Dynamic) {} return 0; }
	public static function state():Int { try { return _state(); } catch (_:Dynamic) {} return FAILED; }
	public static function error():String { try { var e = _error(); return e == null ? "" : e; } catch (_:Dynamic) {} return "ndll funkfmpeg no disponible"; }
	public static function cancel():Void { try { _cancel(); } catch (_:Dynamic) {} }

	#else
	public static function probe(path:String):Null<VideoInfo> return null;
	public static function start(path:String, outDir:String, fpsMilli:Int, width:Int, height:Int, count:Int):Bool return false;
	public static function progress():Int return 0;
	public static function state():Int return FAILED;
	public static function error():String return "VideoFrames nativo no disponible en esta plataforma";
	public static function cancel():Void {}
	#end

	static function parseProbe(text:String):Null<VideoInfo>
	{
		if (text == null || StringTools.startsWith(text, "error:")) return null;
		var parts = text.split(",");
		if (parts.length < 4) return null;
		var w = Std.parseInt(parts[0]);
		var h = Std.parseInt(parts[1]);
		var fps = Std.parseFloat(parts[2]);
		var seconds = Std.parseFloat(parts[3]);
		if (w == null || h == null || w <= 0 || h <= 0) return null;
		return {w: w, h: h, fps: Math.isNaN(fps) || fps <= 0 ? 30 : fps, seconds: Math.isNaN(seconds) ? 0 : seconds};
	}
}

typedef VideoInfo =
{
	var w:Int;
	var h:Int;
	var fps:Float;
	var seconds:Float;
}
