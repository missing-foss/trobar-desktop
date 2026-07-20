// SPDX-FileCopyrightText: 2026 missing-foss
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

/// The outcome of the last sync, persisted on the card
/// (`.trobar/last_sync.json`) so it survives reopening the card — on any
/// machine, even offline. The desktop app itself keeps no per-device state, so
/// this rides with the card like the pairing config does (#20).
class SyncOutcome {
  final DateTime syncedAt;
  final int downloaded;
  final int deleted;

  /// The first error of the last sync, kept so it's copyable for a bug report
  /// and survives a reopen; null once cleared or on a clean sync.
  final String? error;

  const SyncOutcome({
    required this.syncedAt,
    this.downloaded = 0,
    this.deleted = 0,
    this.error,
  });

  /// Same outcome with the error dropped (the "Clear" action) — keeps the
  /// timestamp and counts.
  SyncOutcome withoutError() => SyncOutcome(
        syncedAt: syncedAt,
        downloaded: downloaded,
        deleted: deleted,
      );

  factory SyncOutcome.fromJson(Map<String, dynamic> json) => SyncOutcome(
        syncedAt: DateTime.parse(json['synced_at'] as String),
        downloaded: json['downloaded'] as int? ?? 0,
        deleted: json['deleted'] as int? ?? 0,
        error: json['error'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'synced_at': syncedAt.toIso8601String(),
        'downloaded': downloaded,
        'deleted': deleted,
        if (error != null) 'error': error,
      };
}

class DeviceInfo {
  final String name;
  final String deviceType;
  final int? maxSizeBytes;

  /// null = no artist pictures; 'small' (~512px) or 'full'.
  final String? artistImages;

  const DeviceInfo({
    required this.name,
    required this.deviceType,
    this.maxSizeBytes,
    this.artistImages,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        name: json['name'] as String,
        deviceType: json['device_type'] as String? ?? 'sdcard',
        maxSizeBytes: json['max_size_bytes'] as int?,
        artistImages: json['artist_images'] as String?,
      );
}

class TrackChange {
  final int trackId;

  /// Server-computed on-device path — already FAT/Windows-safe (the server's
  /// _fs_segment guarantees it) and already carrying the correct extension
  /// (incl. .mp3 when the server transcodes for a device). Never derive names
  /// locally. The server serves the already-converted bytes, so the client
  /// just downloads whatever it's given — there is no client-side transcode.
  final String relativePath;
  final int? size;

  const TrackChange({
    required this.trackId,
    required this.relativePath,
    this.size,
  });

  factory TrackChange.fromJson(Map<String, dynamic> json) => TrackChange(
        trackId: json['track_id'] as int,
        relativePath: json['relative_path'] as String,
        size: json['size'] as int?,
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

  const ChangeSet({
    required this.toDownload,
    required this.toDelete,
    required this.downloaded,
    this.playlists = const [],
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
      );
}
