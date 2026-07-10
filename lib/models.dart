// SPDX-License-Identifier: GPL-3.0-or-later
// Wire models for the Trobar device API — deliberately mirrors the Android
// client's field names so the server contract stays visibly identical.

class DeviceConfig {
  final String serverUrl;
  final String token;

  const DeviceConfig({required this.serverUrl, required this.token});

  factory DeviceConfig.fromJson(Map<String, dynamic> json) => DeviceConfig(
        serverUrl: (json['server_url'] as String).trim(),
        token: (json['token'] as String).trim(),
      );

  Map<String, dynamic> toJson() => {'server_url': serverUrl, 'token': token};
}

class DeviceInfo {
  final String name;
  final String deviceType;
  final int? maxSizeBytes;
  final String? transcodeFormat;

  /// null = no artist pictures; 'small' (~512px) or 'full'.
  final String? artistImages;

  const DeviceInfo({
    required this.name,
    required this.deviceType,
    this.maxSizeBytes,
    this.transcodeFormat,
    this.artistImages,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        name: json['name'] as String,
        deviceType: json['device_type'] as String? ?? 'sdcard',
        maxSizeBytes: json['max_size_bytes'] as int?,
        transcodeFormat: json['transcode_format'] as String?,
        artistImages: json['artist_images'] as String?,
      );
}

class TrackChange {
  final int trackId;

  /// Server-computed on-device path — already FAT/Windows-safe (the server's
  /// _fs_segment guarantees it) and already carrying the transcoded
  /// extension on a transcoding device. Never derive names locally.
  final String relativePath;
  final int? size;

  /// true = the client must transcode the downloaded original
  /// before writing. The skeleton (M2) skips these with a clear message;
  /// M3 adds the ffmpeg path.
  final bool transcode;

  const TrackChange({
    required this.trackId,
    required this.relativePath,
    this.size,
    this.transcode = false,
  });

  factory TrackChange.fromJson(Map<String, dynamic> json) => TrackChange(
        trackId: json['track_id'] as int,
        relativePath: json['relative_path'] as String,
        size: json['size'] as int?,
        transcode: json['transcode'] == true,
      );
}

/// a server-generated.m3u8 for one playlist assigned to this
/// device. Written at the card root; content lines carry the marker that
/// makes the file recognisably Trobar-managed.
class PlaylistFile {
  final String name;
  final String filename;
  final String content;

  const PlaylistFile(
      {required this.name, required this.filename, required this.content});

  factory PlaylistFile.fromJson(Map<String, dynamic> json) => PlaylistFile(
        name: json['name'] as String,
        filename: json['filename'] as String,
        content: json['content'] as String,
      );
}

class ChangeSet {
  final List<TrackChange> toDownload;
  final List<TrackChange> toDelete;

  /// What the server believes is already on this device — used only for the
  /// missing-file spot check, never acted on directly.
  final List<TrackChange> downloaded;

  /// every playlist file this device should carry.
  final List<PlaylistFile> playlists;

  /// The format the transcode flags above were computed with — always
  /// prefer this over a separately-fetched device info (a mid-session
  /// format change in the web UI made a stale-info client encode at the
  /// old bitrate).
  final String? transcodeFormat;

  const ChangeSet({
    required this.toDownload,
    required this.toDelete,
    required this.downloaded,
    this.playlists = const [],
    this.transcodeFormat,
  });

  factory ChangeSet.fromJson(Map<String, dynamic> json) => ChangeSet(
        toDownload: [
          for (final t in json['to_download'] as List)
            TrackChange.fromJson(t as Map<String, dynamic>)
        ],
        toDelete: [
          for (final t in json['to_delete'] as List)
            TrackChange.fromJson(t as Map<String, dynamic>)
        ],
        downloaded: [
          for (final t in json['downloaded'] as List)
            TrackChange.fromJson(t as Map<String, dynamic>)
        ],
        playlists: [
          for (final t in (json['playlists'] as List? ?? []))
            PlaylistFile.fromJson(t as Map<String, dynamic>)
        ],
        transcodeFormat: json['transcode_format'] as String?,
      );
}
