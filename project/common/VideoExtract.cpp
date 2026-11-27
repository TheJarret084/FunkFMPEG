/*
 * FunkFMPEG video frame extractor (desktop, C++).
 * Demux/decode/scale: FFmpeg (libavformat, libavcodec, libswscale), enlazado ESTATICO.
 * PNG: stb_image_write.
 * La API Prime (funkfmpeg_video_*) no cambia respecto a versiones anteriores.
 */
// libav va ANTES de hxcpp.h para que los macros de windows.h no le rompan los headers.
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/error.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <libavutil/channel_layout.h>
#include <libavutil/samplefmt.h>
#include <ogg/ogg.h>
#include <vorbis/codec.h>
#include <vorbis/vorbisenc.h>
}

// IMPLEMENT_API: este es el UNICO .cpp del ndll que define el loader de CFFI (val_*, alloc_*).
#define IMPLEMENT_API
#include <hxcpp.h>
#include <hx/CFFIPrime.h>

// hxcpp/FFmpeg pueden des definir INT_MAX: lo garantizamos antes de los headers de C++ y stb.
#ifndef INT_MAX
#define INT_MAX 0x7fffffff
#endif

#include <string>
#include <vector>
#include <atomic>
#include <mutex>
#include <thread>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <sys/stat.h>

#ifdef _WIN32
#include <direct.h>
#define MKDIR(p) _mkdir(p)
#else
#include <unistd.h>
#define MKDIR(p) mkdir(p, 0755)
#endif

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "../lib_stb/stb_image_write.h"

static std::string av_err(int e) {
	char b[AV_ERROR_MAX_STRING_SIZE] = {0};
	av_strerror(e, b, sizeof(b));
	return std::string(b);
}

static bool ensure_dir(const std::string &path) {
	if (path.empty()) return false;
	struct stat st;
	if (stat(path.c_str(), &st) == 0) return (st.st_mode & S_IFDIR) != 0;
	std::string cur;
	for (size_t i = 0; i < path.size(); ++i) {
		cur.push_back(path[i]);
		if (path[i] == '/' || path[i] == '\\' || i == path.size() - 1) {
			if (cur.size() <= 1) continue;
			struct stat s2;
			if (stat(cur.c_str(), &s2) != 0) MKDIR(cur.c_str());
		}
	}
	return stat(path.c_str(), &st) == 0 && (st.st_mode & S_IFDIR) != 0;
}

// ---------------------------------------------------------------- abrir

struct Source {
	AVFormatContext *fmt = nullptr;
	AVCodecContext *cc = nullptr;
	AVStream *st = nullptr;
	int vi = -1;
	SwsContext *sws = nullptr;
	AVPacket *pkt = nullptr;
	AVFrame *frame = nullptr;
	~Source() {
		if (sws) sws_freeContext(sws);
		av_frame_free(&frame);
		av_packet_free(&pkt);
		avcodec_free_context(&cc);
		avformat_close_input(&fmt);
	}
};

// Abre el contenedor y localiza el mejor stream (video por defecto, o audio). Si decode=true abre tambien el decoder.
static bool open_source(Source &s, const std::string &path, bool decode, std::string &err, AVMediaType type = AVMEDIA_TYPE_VIDEO) {
	av_log_set_level(AV_LOG_ERROR);
	int e = avformat_open_input(&s.fmt, path.c_str(), nullptr, nullptr);
	if (e < 0) { err = "no se pudo abrir video: " + av_err(e); return false; }
	e = avformat_find_stream_info(s.fmt, nullptr);
	// En mp4 cortos/con mdat de 64 bits FFmpeg puede devolver AVERROR_INVALIDDATA/EOF
	// despues de haber llenado los streams. ffprobe lo tolera; nosotros tambien.
	if (e < 0 && s.fmt->nb_streams == 0) { err = "no se pudo leer info del video: " + av_err(e); return false; }
	s.vi = av_find_best_stream(s.fmt, type, -1, -1, nullptr, 0);
	if (s.vi < 0) { err = (type == AVMEDIA_TYPE_AUDIO) ? "no hay stream de audio" : "no hay stream de video"; return false; }
	s.st = s.fmt->streams[s.vi];
	if (!decode) return true;

	const AVCodec *codec = avcodec_find_decoder(s.st->codecpar->codec_id);
	if (!codec) { err = "codec no soportado en este build de FFmpeg"; return false; }
	s.cc = avcodec_alloc_context3(codec);
	if (!s.cc) { err = "sin memoria (codec)"; return false; }
	e = avcodec_parameters_to_context(s.cc, s.st->codecpar);
	if (e < 0) { err = "parametros del codec: " + av_err(e); return false; }
	s.cc->thread_count = 0; // auto
	e = avcodec_open2(s.cc, codec, nullptr);
	if (e < 0) { err = "no se pudo abrir el decoder: " + av_err(e); return false; }
	s.pkt = av_packet_alloc();
	s.frame = av_frame_alloc();
	if (!s.pkt || !s.frame) { err = "sin memoria (packet/frame)"; return false; }
	return true;
}

static double stream_fps(Source &s) {
	AVRational fr = av_guess_frame_rate(s.fmt, s.st, nullptr);
	double fps = (fr.num > 0 && fr.den > 0) ? av_q2d(fr) : 0.0;
	return (fps > 0.0 && !std::isnan(fps)) ? fps : 30.0;
}

static double stream_seconds(Source &s) {
	if (s.fmt->duration != AV_NOPTS_VALUE) return (double)s.fmt->duration / (double)AV_TIME_BASE;
	if (s.st->duration != AV_NOPTS_VALUE) return (double)s.st->duration * av_q2d(s.st->time_base);
	return 0.0;
}

// ---------------------------------------------------------------- probe

static void set_error(const std::string &e);

static std::string probe_video(const std::string &path) {
	Source s;
	std::string err;
	if (!open_source(s, path, false, err)) { set_error(err); return "error:" + err; }
	int w = s.st->codecpar->width, h = s.st->codecpar->height;
	if (w <= 0 || h <= 0) return "error:tamano invalido";
	char buf[128];
	snprintf(buf, sizeof(buf), "%d,%d,%.4f,%.4f", w, h, stream_fps(s), stream_seconds(s));
	return std::string(buf);
}

// ---------------------------------------------------------------- extraccion

static std::atomic<int> g_state(0); // 0 idle,1 running,2 done,3 failed,4 cancelled
static std::atomic<int> g_progress(0);
static std::atomic<bool> g_cancel(false);
static std::mutex g_errMutex;
static std::string g_error;

static void set_error(const std::string &e) {
	std::lock_guard<std::mutex> lock(g_errMutex);
	g_error = e;
}

struct Scaler {
	int lastFmt = -1, lastW = 0, lastH = 0, lastSpc = -1, lastRange = -1;
};

// Convierte el frame decodificado a RGBA del tamano de salida. BT.601/709 y rango segun el stream.
static bool convert_rgba(Source &s, Scaler &sc, const AVFrame *f, int outW, int outH, std::vector<unsigned char> &out) {
	bool downscale = outW < f->width || outH < f->height;
	s.sws = sws_getCachedContext(s.sws, f->width, f->height, (AVPixelFormat)f->format,
		outW, outH, AV_PIX_FMT_RGBA, downscale ? SWS_AREA : SWS_BILINEAR, nullptr, nullptr, nullptr);
	if (!s.sws) return false;

	int spc = (int)f->colorspace, range = (int)f->color_range;
	if (sc.lastFmt != f->format || sc.lastW != f->width || sc.lastH != f->height || sc.lastSpc != spc || sc.lastRange != range) {
		int cs = SWS_CS_DEFAULT;
		if (f->colorspace == AVCOL_SPC_BT709) cs = SWS_CS_ITU709;
		else if (f->colorspace == AVCOL_SPC_BT2020_NCL || f->colorspace == AVCOL_SPC_BT2020_CL) cs = SWS_CS_BT2020;
		else if (f->colorspace == AVCOL_SPC_UNSPECIFIED && f->height >= 720) cs = SWS_CS_ITU709; // HD sin etiqueta
		const int *coef = sws_getCoefficients(cs);
		int srcRange = (f->color_range == AVCOL_RANGE_JPEG) ? 1 : 0;
		sws_setColorspaceDetails(s.sws, coef, srcRange, sws_getCoefficients(SWS_CS_DEFAULT), 1, 0, 1 << 16, 1 << 16);
		sc.lastFmt = f->format; sc.lastW = f->width; sc.lastH = f->height; sc.lastSpc = spc; sc.lastRange = range;
	}

	out.resize((size_t)outW * outH * 4);
	uint8_t *dst[4] = { &out[0], nullptr, nullptr, nullptr };
	int dstStride[4] = { outW * 4, 0, 0, 0 };
	int h = sws_scale(s.sws, f->data, f->linesize, 0, f->height, dst, dstStride);
	return h > 0;
}

static void extract_frames(const std::string &path, const std::string &outDir, int fpsMilli, int outW, int outH, int count) {
	g_progress = 0;
	g_cancel = false;
	set_error("");
	g_state = 1;

	if (outW <= 0 || outH <= 0 || count <= 0) { set_error("parametros invalidos"); g_state = 3; return; }
	if (!ensure_dir(outDir)) { set_error("no se pudo crear dir"); g_state = 3; return; }

	Source s;
	std::string err;
	if (!open_source(s, path, true, err)) { set_error(err); g_state = 3; return; }

	double srcFps = stream_fps(s);
	double tgtFps = fpsMilli > 0 ? fpsMilli / 1000.0 : 24.0;
	double tol = 0.5 / srcFps; // medio frame de la fuente
	double timeBase = av_q2d(s.st->time_base);
	int64_t startTs = (s.st->start_time != AV_NOPTS_VALUE) ? s.st->start_time : 0;

	std::string dir = outDir;
	if (!dir.empty() && dir[dir.size() - 1] != '/' && dir[dir.size() - 1] != '\\') dir += "/";

	Scaler sc;
	std::vector<unsigned char> rgba;
	int written = 0;
	int decoded = 0;
	bool failed = false;

	// Toma un frame decodificado: lo escribe las veces que le toque segun el fps objetivo.
	auto handleFrame = [&](AVFrame *f) -> bool {
		double t;
		if (f->best_effort_timestamp == AV_NOPTS_VALUE) t = (double)decoded / srcFps;
		else t = (double)(f->best_effort_timestamp - startTs) * timeBase;
		if (t < 0) t = 0;
		bool converted = false;
		while (written < count && t + tol >= (double)written / tgtFps) {
			if (!converted) {
				if (!convert_rgba(s, sc, f, outW, outH, rgba)) { set_error("fallo sws_scale"); return false; }
				converted = true;
			}
			char name[64];
			snprintf(name, sizeof(name), "f%06d.png", written + 1);
			std::string outPath = dir + name;
			if (!stbi_write_png(outPath.c_str(), outW, outH, 4, &rgba[0], outW * 4)) { set_error("no se pudo escribir png"); return false; }
			written++;
			g_progress = written;
		}
		decoded++;
		return true;
	};

	// Saca todos los frames pendientes del decoder. 0 = sigue, 1 = terminado/EOF, -1 = error.
	auto drain = [&]() -> int {
		for (;;) {
			int e = avcodec_receive_frame(s.cc, s.frame);
			if (e == AVERROR(EAGAIN)) return 0;
			if (e == AVERROR_EOF) return 1;
			if (e < 0) { set_error("decode: " + av_err(e)); return -1; }
			bool ok = handleFrame(s.frame);
			av_frame_unref(s.frame);
			if (!ok) return -1;
			if (written >= count) return 1;
			if (g_cancel) return 0;
		}
	};

	bool done = false;
	while (!done && !failed) {
		if (g_cancel) break;
		int e = av_read_frame(s.fmt, s.pkt);
		if (e < 0) break; // EOF o error de lectura: pasamos al flush
		if (s.pkt->stream_index != s.vi) { av_packet_unref(s.pkt); continue; }
		e = avcodec_send_packet(s.cc, s.pkt);
		av_packet_unref(s.pkt);
		if (e < 0 && e != AVERROR(EAGAIN) && e != AVERROR_INVALIDDATA) { set_error("send_packet: " + av_err(e)); failed = true; break; }
		int r = drain();
		if (r < 0) failed = true;
		else if (r == 1) done = true;
	}

	if (!failed && !done && !g_cancel) {
		avcodec_send_packet(s.cc, nullptr); // flush
		if (drain() < 0) failed = true;
	}

	if (failed) { g_state = 3; return; }
	if (g_cancel) { set_error("cancelado"); g_state = 4; return; }
	if (written <= 0) { set_error("no se decodifico ningun frame"); g_state = 3; return; }
	g_state = 2;
}

// ---------------------------------------------------------------- audio -> OGG (Vorbis)

static std::mutex g_audioMutex;
static std::string g_audioError;

static void set_audio_error(const std::string &e) {
	std::lock_guard<std::mutex> lock(g_audioMutex);
	g_audioError = e;
}

static std::string probe_audio(const std::string &path) {
	Source s;
	std::string err;
	if (!open_source(s, path, false, err, AVMEDIA_TYPE_AUDIO)) return "error:" + err;
	int sr = s.st->codecpar->sample_rate;
	int ch = s.st->codecpar->ch_layout.nb_channels;
	if (sr <= 0 || ch <= 0) return "error:audio invalido";
	char buf[96];
	snprintf(buf, sizeof(buf), "%d,%d,%.4f", sr, ch, stream_seconds(s));
	return std::string(buf);
}

struct OggOut {
	FILE *f = nullptr;
	SwrContext *swr = nullptr;
	vorbis_info vi;
	vorbis_comment vc;
	vorbis_dsp_state vd;
	vorbis_block vb;
	ogg_stream_state os;
	bool viOk = false, vcOk = false, vdOk = false, vbOk = false, osOk = false;
	~OggOut() {
		if (osOk) ogg_stream_clear(&os);
		if (vbOk) vorbis_block_clear(&vb);
		if (vdOk) vorbis_dsp_clear(&vd);
		if (vcOk) vorbis_comment_clear(&vc);
		if (viOk) vorbis_info_clear(&vi);
		if (swr) swr_free(&swr);
		if (f) fclose(f);
	}
};

// Decodifica el mejor stream de audio (de un audio o de un video) y lo codifica a OGG Vorbis (VBR).
// quality 0..10 (5 ~ 160 kbps). rate/channels <= 0 usan los del origen (canales: max 2).
static int audio_to_ogg(const std::string &path, const std::string &outPath, int rate, int channels, int quality) {
	Source s;
	std::string err;
	if (!open_source(s, path, true, err, AVMEDIA_TYPE_AUDIO)) { set_audio_error(err); return 0; }
	int srcCh = s.cc->ch_layout.nb_channels;
	if (rate <= 0) rate = s.cc->sample_rate;
	if (channels <= 0) channels = (srcCh >= 1 && srcCh <= 2) ? srcCh : 2;
	if (quality < 0) quality = 0;
	if (quality > 10) quality = 10;
	if (rate <= 0 || channels > 8) { set_audio_error("parametros de audio invalidos"); return 0; }
	if (s.cc->ch_layout.order == AV_CHANNEL_ORDER_UNSPEC) av_channel_layout_default(&s.cc->ch_layout, srcCh);

	OggOut o;
	AVChannelLayout outL;
	av_channel_layout_default(&outL, channels);
	int e = swr_alloc_set_opts2(&o.swr, &outL, AV_SAMPLE_FMT_FLTP, rate, &s.cc->ch_layout, s.cc->sample_fmt, s.cc->sample_rate, 0, nullptr);
	av_channel_layout_uninit(&outL);
	if (e >= 0 && o.swr) e = swr_init(o.swr);
	if (e < 0 || !o.swr) { set_audio_error("swresample: " + av_err(e)); return 0; }

	vorbis_info_init(&o.vi); o.viOk = true;
	if (vorbis_encode_init_vbr(&o.vi, channels, rate, quality / 10.0f) != 0) { set_audio_error("vorbis: sample rate/canales no soportados"); return 0; }
	vorbis_comment_init(&o.vc); o.vcOk = true;
	vorbis_comment_add_tag(&o.vc, "ENCODER", "FunkFMPEG");
	if (vorbis_analysis_init(&o.vd, &o.vi) != 0) { set_audio_error("vorbis_analysis_init fallo"); return 0; }
	o.vdOk = true;
	if (vorbis_block_init(&o.vd, &o.vb) != 0) { set_audio_error("vorbis_block_init fallo"); return 0; }
	o.vbOk = true;
	ogg_stream_init(&o.os, 0x4B4E5546); o.osOk = true;

	o.f = fopen(outPath.c_str(), "wb");
	if (!o.f) { set_audio_error("no se pudo crear el ogg"); return 0; }

	std::string fail;
	ogg_page og;
	ogg_packet op;

	auto writePages = [&](bool flush) -> bool {
		for (;;) {
			int r = flush ? ogg_stream_flush(&o.os, &og) : ogg_stream_pageout(&o.os, &og);
			if (r <= 0) return true;
			if (fwrite(og.header, 1, (size_t)og.header_len, o.f) != (size_t)og.header_len ||
				fwrite(og.body, 1, (size_t)og.body_len, o.f) != (size_t)og.body_len) { fail = "no se pudo escribir el ogg"; return false; }
		}
	};

	{
		ogg_packet h1, h2, h3;
		vorbis_analysis_headerout(&o.vd, &o.vc, &h1, &h2, &h3);
		ogg_stream_packetin(&o.os, &h1);
		ogg_stream_packetin(&o.os, &h2);
		ogg_stream_packetin(&o.os, &h3);
		if (!writePages(true)) { set_audio_error(fail); return 0; }
	}

	auto encodeBlocks = [&]() -> bool {
		while (vorbis_analysis_blockout(&o.vd, &o.vb) == 1) {
			vorbis_analysis(&o.vb, nullptr);
			vorbis_bitrate_addblock(&o.vb);
			while (vorbis_bitrate_flushpacket(&o.vd, &op)) {
				ogg_stream_packetin(&o.os, &op);
				if (!writePages(false)) return false;
			}
		}
		return true;
	};

	uint64_t samples = 0;
	// Resamplea a float planar directo en el buffer de vorbis. in=null hace flush del resampler.
	auto convert = [&](const uint8_t **in, int inSamples) -> int {
		int maxOut = swr_get_out_samples(o.swr, inSamples);
		if (maxOut <= 0) return 0;
		float **buf = vorbis_analysis_buffer(&o.vd, maxOut);
		uint8_t *planes[8] = {0};
		for (int c = 0; c < channels; ++c) planes[c] = (uint8_t *)buf[c];
		int n = swr_convert(o.swr, planes, maxOut, in, inSamples);
		if (n < 0) { fail = "swr_convert: " + av_err(n); return -1; }
		if (n > 0) {
			vorbis_analysis_wrote(&o.vd, n);
			samples += (uint64_t)n;
			if (!encodeBlocks()) return -1;
		}
		return n;
	};

	auto drain = [&]() -> bool {
		for (;;) {
			int r = avcodec_receive_frame(s.cc, s.frame);
			if (r == AVERROR(EAGAIN) || r == AVERROR_EOF) return true;
			if (r < 0) { fail = "decode: " + av_err(r); return false; }
			int n = convert((const uint8_t **)s.frame->extended_data, s.frame->nb_samples);
			av_frame_unref(s.frame);
			if (n < 0) return false;
		}
	};

	bool ok = true;
	while (ok && av_read_frame(s.fmt, s.pkt) >= 0) {
		if (s.pkt->stream_index != s.vi) { av_packet_unref(s.pkt); continue; }
		int r = avcodec_send_packet(s.cc, s.pkt);
		av_packet_unref(s.pkt);
		if (r < 0 && r != AVERROR(EAGAIN) && r != AVERROR_INVALIDDATA) { fail = "send_packet: " + av_err(r); ok = false; break; }
		ok = drain();
	}
	if (ok) {
		avcodec_send_packet(s.cc, nullptr);
		ok = drain();
	}
	if (ok && convert(nullptr, 0) < 0) ok = false; // flush del resampler
	if (ok) {
		vorbis_analysis_wrote(&o.vd, 0); // fin de stream
		ok = encodeBlocks() && writePages(true);
	}

	if (!ok) { set_audio_error(fail); return 0; }
	if (samples == 0) { set_audio_error("no se decodifico audio"); return 0; }
	return 1;
}

// ---------------------------------------------------------------- Prime

static HxString funkfmpeg_video_probe(HxString path) {
	std::string out = probe_video(path.c_str());
	return HxString(out.c_str(), (int)out.size(), true);
}
DEFINE_PRIME1(funkfmpeg_video_probe);

static int funkfmpeg_video_start(HxString path, HxString outDir, int fpsMilli, int width, int height, int count) {
	if (g_state == 1) return 0;
	g_cancel = false;
	set_error("");
	g_progress = 0;
	g_state = 1;
	std::string p = path.c_str();
	std::string o = outDir.c_str();
	try {
		std::thread([p, o, fpsMilli, width, height, count]() {
			extract_frames(p, o, fpsMilli, width, height, count);
		}).detach();
	} catch (...) {
		set_error("no se pudo iniciar hilo");
		g_state = 3;
		return 0;
	}
	return 1;
}
DEFINE_PRIME6(funkfmpeg_video_start);

static int funkfmpeg_video_progress() { return g_progress; }
DEFINE_PRIME0(funkfmpeg_video_progress);

static int funkfmpeg_video_state() { return g_state; }
DEFINE_PRIME0(funkfmpeg_video_state);

static HxString funkfmpeg_video_error() {
	std::lock_guard<std::mutex> lock(g_errMutex);
	return HxString(g_error.c_str(), (int)g_error.size(), true);
}
DEFINE_PRIME0(funkfmpeg_video_error);

static void funkfmpeg_video_cancel() { g_cancel = true; }
DEFINE_PRIME0v(funkfmpeg_video_cancel);

static HxString funkfmpeg_audio_probe(HxString path) {
	std::string out = probe_audio(path.c_str());
	return HxString(out.c_str(), (int)out.size(), true);
}
DEFINE_PRIME1(funkfmpeg_audio_probe);

// Bloqueante: llamar desde un hilo propio si no quieres congelar el juego.
static int funkfmpeg_audio_to_ogg(HxString src, HxString dst, int rate, int channels, int quality) {
	return audio_to_ogg(src.c_str(), dst.c_str(), rate, channels, quality);
}
DEFINE_PRIME5(funkfmpeg_audio_to_ogg);

static HxString funkfmpeg_audio_error() {
	std::lock_guard<std::mutex> lock(g_audioMutex);
	return HxString(g_audioError.c_str(), (int)g_audioError.size(), true);
}
DEFINE_PRIME0(funkfmpeg_audio_error);

// Android (Lime) enlaza el ndll de forma estatica: hxcpp busca <nombre>_register_prims().
#ifdef STATIC_LINK
extern "C" int funkfmpeg_register_prims() { return 0; }
#endif
