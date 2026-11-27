package funkfmpeg;

#if cpp
import cpp.ConstCharStar;
import cpp.Prime;
#end

/**
 * Extraccion de frames de video para FunkFMPEG.
 *
 * cpp (Windows/Linux/Android 64): ndll nativo C++ con FFmpeg (libavformat/libavcodec/libswscale) enlazado estatico.
 * La API Prime usa enteros y `const char*` (no `String`) porque el marshalling de HxString
 * devolvia 0 en Android y hacia creer que el video no se podia leer.
 */
class VideoFrames
{
	public static inline var IDLE:Int = 0;
	public static inline var RUNNING:Int = 1;
	public static inline var DONE:Int = 2;
	public static inline var FAILED:Int = 3;
	public static inline var CANCELLED:Int = 4;

	#if cpp
	static var _probeI:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_probe_i", "ci");
	static var _probeW:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_probe_w_i", "ii");
	static var _probeH:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_probe_h_i", "ii");
	static var _probeFps:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_probe_fps_i", "ii");
	static var _probeSeconds:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_probe_seconds_i", "ii");
	static var _startC:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_start_c", "cciiiii");
	static var _progressI:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_progress_i", "ii");
	static var _stateI:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_state_i", "ii");
	static var _errorLen:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_error_len_i", "ii");
	static var _errorAt:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_error_at_i", "ii");
	static var _cancelI:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_video_cancel_i", "ii");

	static var lastError:String = "";

	public static function probe(path:String):Null<VideoInfo>
	{
		lastError = "";
		try
		{
			if (_probeI(ConstCharStar.fromString(path)) != 1)
			{
				lastError = readNativeError();
				if (lastError == "") lastError = "no se pudo leer el video (decoder nativo)";
				return null;
			}

			var w = Std.int(_probeW(0));
			var h = Std.int(_probeH(0));
			var fpsMilli = Std.int(_probeFps(0));
			var secondsMilli = Std.int(_probeSeconds(0));
			if (w <= 0 || h <= 0)
			{
				lastError = "tamano de video invalido";
				return null;
			}

			var fps = fpsMilli / 1000;
			var seconds = secondsMilli / 1000;
			return {
				w: w,
				h: h,
				fps: fps > 0 ? fps : 30,
				seconds: seconds > 0 ? seconds : 0
			};
		}
		catch (e:Dynamic)
		{
			lastError = Std.string(e);
			return null;
		}
	}

	public static function start(path:String, outDir:String, fpsMilli:Int, width:Int, height:Int, count:Int):Bool
	{
		lastError = "";
		try
		{
			return _startC(ConstCharStar.fromString(path), ConstCharStar.fromString(outDir), fpsMilli, width, height, count) == 1;
		}
		catch (e:Dynamic)
		{
			lastError = Std.string(e);
			return false;
		}
	}

	public static function progress():Int
	{
		try { return Std.int(_progressI(0)); } catch (_:Dynamic) {}
		return 0;
	}

	public static function state():Int
	{
		try { return Std.int(_stateI(0)); } catch (_:Dynamic) {}
		return FAILED;
	}

	public static function error():String
	{
		if (lastError != "" && lastError != "0") return lastError;
		return readNativeError();
	}

	public static function cancel():Void
	{
		try { _cancelI(0); } catch (_:Dynamic) {}
	}

	/** El error nativo se lee byte a byte para no depender del marshalling de String. */
	static function readNativeError():String
	{
		try
		{
			var n = Std.int(_errorLen(0));
			if (n <= 0 || n > 4096) return "";
			var out = "";
			for (i in 0...n) out += String.fromCharCode(Std.int(_errorAt(i)) & 0xFF);
			return out;
		}
		catch (_:Dynamic) {}
		return "";
	}
	#else
	public static function probe(path:String):Null<VideoInfo> return null;
	public static function start(path:String, outDir:String, fpsMilli:Int, width:Int, height:Int, count:Int):Bool return false;
	public static function progress():Int return 0;
	public static function state():Int return FAILED;
	public static function error():String return "VideoFrames nativo no disponible en esta plataforma";
	public static function cancel():Void {}
	#end
}

typedef VideoInfo =
{
	var w:Int;
	var h:Int;
	var fps:Float;
	var seconds:Float;
}
