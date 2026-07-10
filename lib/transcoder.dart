// SPDX-License-Identifier: GPL-3.0-or-later
// gitea#2 M3 — the lossless→MP3 320 path. The server decides *what* gets
// transcoded (the `transcode` flag in /changes); this only knows *how*.

import 'dart:io';

import 'package:path/path.dart' as p;

class TranscodeException implements Exception {
  final String message;
  TranscodeException(this.message);
  @override
  String toString() => message;
}

/// Injectable so the sync engine is testable without a real encoder.
abstract class Transcoder {
  /// [format] is the server's device format string (e.g. 'mp3_320').
  Future<void> transcode(File src, File dest, String format);
}

/// Server format string → ffmpeg bitrate. Kept in sync with the server's
/// TRANSCODE_FORMATS; an unknown value means the server is newer than this
/// client build.
const mp3Bitrates = {
  'mp3_320': '320k',
  'mp3_256': '256k',
  'mp3_192': '192k',
  'mp3_128': '128k',
};

class FfmpegTranscoder implements Transcoder {
  final String binary;
  FfmpegTranscoder(this.binary);

  /// Bundled binary (next to the executable) first, then PATH. Null means
  /// transcoding devices can't be synced on this machine — surfaced in the
  /// UI, never a silent skip.
  static Future<FfmpegTranscoder?> locate() async {
    final name = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    final bundled =
        File(p.join(File(Platform.resolvedExecutable).parent.path, name));
    if (await bundled.exists()) return FfmpegTranscoder(bundled.path);
    try {
      final r = await Process.run(
          Platform.isWindows ? 'where' : 'which', [name]);
      final found = (r.stdout as String).trim().split('\n').first;
      if (r.exitCode == 0 && found.isNotEmpty) {
        return FfmpegTranscoder(found);
      }
    } on ProcessException {
      // no `which`/`where` — fall through
    }
    return null;
  }

  @override
  Future<void> transcode(File src, File dest, String format) async {
    final bitrate = mp3Bitrates[format];
    if (bitrate == null) {
      throw TranscodeException(
          'unsupported transcode format "$format" — update Trobar desktop');
    }
    final r = await Process.run(binary, [
      '-hide_banner', '-loglevel', 'error', '-y',
      '-i', src.path,
      // First audio stream + the cover art if there is one. Explicit maps:
      // a plain `-map 0` would abort on any exotic extra stream.
      '-map', '0:a:0', '-map', '0:v:0?',
      '-c:a', 'libmp3lame', '-b:a', bitrate,
      '-c:v', 'copy',
      // Tags carry over; ID3v2.3 for old-DAP compatibility (v2.4 support
      // is still patchy on hardware players).
      '-map_metadata', '0',
      '-id3v2_version', '3',
      // Output goes to a .part file, so the muxer can't be guessed from
      // the extension.
      '-f', 'mp3',
      dest.path,
    ]);
    if (r.exitCode != 0) {
      final detail =
          (r.stderr as String).trim().split('\n').take(2).join(' | ');
      throw TranscodeException('ffmpeg failed (${r.exitCode}): $detail');
    }
  }
}
