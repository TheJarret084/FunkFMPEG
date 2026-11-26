#!/bin/sh
# FFmpeg minimo (LGPL, estatico, sin red ni libs externas) desde el tag OFICIAL.
# Uso: building/build_ffmpeg.sh <prefix> [flags extra de configure]
#   Linux/mac:  building/build_ffmpeg.sh "$PWD/project/ffmpeg"
#   Windows:    en MSYS2 con el entorno de MSVC cargado y  --toolchain=msvc
set -e

FFMPEG_TAG="${FFMPEG_TAG:-n7.1.1}"
PREFIX="$1"; shift || true
[ -n "$PREFIX" ] || { echo "uso: $0 <prefix> [flags]"; exit 1; }
SRC="${FFMPEG_SRC:-$(pwd)/ffmpeg-src}"

[ -d "$SRC/.git" ] || git clone --depth 1 --branch "$FFMPEG_TAG" https://github.com/FFmpeg/FFmpeg.git "$SRC"
cd "$SRC"

./configure \
	--prefix="$PREFIX" \
	--enable-static --disable-shared --enable-pic \
	--disable-programs --disable-doc --disable-debug \
	--disable-autodetect --disable-network \
	--disable-avdevice --disable-avfilter \
	--disable-everything \
	--enable-protocol=file \
	--enable-demuxer=mov,matroska,avi,flv,mpegts,mpegps,ogg,gif,mpegvideo,h264,hevc,mp3,wav,flac,aac \
	--enable-parser=h264,hevc,vp8,vp9,av1,mpeg4video,mpegvideo,mpegaudio,aac,opus,vorbis,flac \
	--enable-decoder=h264,hevc,vp8,vp9,mpeg4,mpeg2video,mpeg1video,msmpeg4v1,msmpeg4v2,msmpeg4v3,wmv1,wmv2,wmv3,theora,vp6,vp6f,flv,gif,mjpeg,png,prores,rawvideo,mp3,mp3float,aac,vorbis,opus,flac,alac,pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le,pcm_u8,adpcm_ima_wav,adpcm_ms \
	"$@"

make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
make install
echo "FFmpeg $FFMPEG_TAG listo en $PREFIX"
