# Third-party

- **FFmpeg** (libavformat, libavcodec, libswscale, libavutil) — LGPL v2.1+. Built from the official
  tag set in `building/build_ffmpeg.sh` (`FFMPEG_TAG`), without `--enable-gpl` / `--enable-nonfree`,
  linked statically into `funkfmpeg.ndll`. The exact configure flags are in that script, so anyone
  can rebuild the ndll against their own FFmpeg: `haxelib run hxcpp Build.xml -DFFMPEG_DIR=<prefix>`.
  Source: https://ffmpeg.org / https://github.com/FFmpeg/FFmpeg
- **stb_image_write** — public domain / MIT (Sean Barrett). `project/lib_stb/`.
- **libogg / libvorbis** — BSD-3-Clause (Xiph.Org). Downloaded by `building/fetch_vorbis.sh` and compiled into the ndll to write OGG Vorbis.
