#!/bin/sh
# Baja libogg + libvorbis (Xiph, BSD-3) a project/lib_ogg y project/lib_vorbis para compilarlos
# junto al ndll con hxcpp (mismo compilador en Windows/Linux/Android, sin cmake).
set -e
OGG_VER="${OGG_VER:-1.3.5}"
VORBIS_VER="${VORBIS_VER:-1.3.7}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/funkfmpeg_xiph"
rm -rf "$TMP" "$ROOT/project/lib_ogg" "$ROOT/project/lib_vorbis"
mkdir -p "$TMP" "$ROOT/project/lib_ogg" "$ROOT/project/lib_vorbis"
cd "$TMP"

curl -fsSL -o ogg.tgz "https://downloads.xiph.org/releases/ogg/libogg-$OGG_VER.tar.gz"
curl -fsSL -o vorbis.tgz "https://downloads.xiph.org/releases/vorbis/libvorbis-$VORBIS_VER.tar.gz"
tar xzf ogg.tgz
tar xzf vorbis.tgz

cp -r "libogg-$OGG_VER/include" "$ROOT/project/lib_ogg/include"
cp -r "libogg-$OGG_VER/src" "$ROOT/project/lib_ogg/src"
cp -r "libvorbis-$VORBIS_VER/include" "$ROOT/project/lib_vorbis/include"
cp -r "libvorbis-$VORBIS_VER/lib" "$ROOT/project/lib_vorbis/lib"

# libogg: este header lo genera configure/cmake; con stdint basta.
cat > "$ROOT/project/lib_ogg/include/ogg/config_types.h" <<'H'
#ifndef __CONFIG_TYPES_H__
#define __CONFIG_TYPES_H__
#include <stdint.h>
typedef int16_t ogg_int16_t;
typedef uint16_t ogg_uint16_t;
typedef int32_t ogg_int32_t;
typedef uint32_t ogg_uint32_t;
typedef int64_t ogg_int64_t;
typedef uint64_t ogg_uint64_t;
#endif
H
echo "libogg $OGG_VER + libvorbis $VORBIS_VER listos en project/"
