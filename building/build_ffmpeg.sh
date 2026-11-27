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
	--enable-everything \
	--enable-protocol=file \
	"$@"

make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
make install
echo "FFmpeg $FFMPEG_TAG listo en $PREFIX"
