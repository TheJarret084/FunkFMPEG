package funkfmpeg;

#if cpp
import cpp.Prime;
#end

/** Audio via FFmpeg (ndll). Decodifica mp3/ogg/opus/flac/aac/wav, o el audio de un video, y lo guarda como OGG Vorbis (unica salida). */
class AudioTools
{
	#if cpp
	static var _probe:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_audio_probe", "ss");
	static var _toOgg:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_audio_to_ogg", "ssiiii");
	static var _error:Dynamic = Prime.load("funkfmpeg", "funkfmpeg_audio_error", "s");

	public static function probe(path:String):Null<AudioInfo>
	{
		try
		{
			var text:String = _probe(path);
			if (text == null || StringTools.startsWith(text, "error:")) return null;
			var p = text.split(",");
			if (p.length < 3) return null;
			var sr = Std.parseInt(p[0]);
			var ch = Std.parseInt(p[1]);
			var sec = Std.parseFloat(p[2]);
			if (sr == null || ch == null || sr <= 0 || ch <= 0) return null;
			return {sampleRate: sr, channels: ch, seconds: Math.isNaN(sec) ? 0 : sec};
		}
		catch (_:Dynamic) {}
		return null;
	}

	/** Bloqueante. quality 0..10 (VBR). sampleRate/channels <= 0 usan el original (canales: max 2). */
	public static function toOgg(src:String, dstOgg:String, sampleRate:Int, channels:Int, quality:Int):Bool
	{
		try { return _toOgg(src, dstOgg, sampleRate, channels, quality) == 1; }
		catch (_:Dynamic) {}
		return false;
	}

	public static function error():String
	{
		try { var e:String = _error(); return e == null ? "" : e; }
		catch (_:Dynamic) {}
		return "ndll funkfmpeg no disponible";
	}
	#else
	public static function probe(path:String):Null<AudioInfo> return null;
	public static function toOgg(src:String, dstOgg:String, sampleRate:Int, channels:Int, quality:Int):Bool return false;
	public static function error():String return "AudioTools nativo no disponible en esta plataforma";
	#end
}

typedef AudioInfo =
{
	var sampleRate:Int;
	var channels:Int;
	var seconds:Float;
}
