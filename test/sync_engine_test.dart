// SPDX-License-Identifier: GPL-3.0-or-later
// Engine-level tests against a fake HTTP layer and a temp-dir "card" —
// covers the M2 contract: atomic writes, real-bytes ack, transcode skip,
// delete + empty-dir pruning, and the missing-file spot check.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:trobar_desktop/api_client.dart';
import 'package:trobar_desktop/models.dart';
import 'package:trobar_desktop/sync_engine.dart';

const _config = DeviceConfig(serverUrl: 'http://srv', token: 't0k');

ApiClient _client(Map<int, List<int>> files, List<Map<String, dynamic>> acks,
    {Map<String, List<int>> artistImages = const {}, List<Uri>? imageRequests}) {
  return ApiClient(_config, httpClient: MockClient.streaming((req, body) async {
    if (req.url.path == '/api/device/artist-image') {
      imageRequests?.add(req.url);
      final img = artistImages[req.url.queryParameters['artist']];
      if (img == null) return http.StreamedResponse(const Stream.empty(), 404);
      return http.StreamedResponse(Stream.value(img), 200);
    }
    if (req.url.path.startsWith('/api/device/file/')) {
      final id = int.parse(req.url.pathSegments.last);
      final content = files[id];
      if (content == null) {
        return http.StreamedResponse(const Stream.empty(), 404);
      }
      return http.StreamedResponse(Stream.value(content), 200);
    }
    if (req.url.path == '/api/device/ack') {
      acks.add(jsonDecode(await utf8.decodeStream(body)) as Map<String, dynamic>);
      return http.StreamedResponse(Stream.value(utf8.encode('{"status":"ok"}')), 200);
    }
    if (req.url.path == '/api/device/storage') {
      return http.StreamedResponse(Stream.value(utf8.encode('{"status":"ok"}')), 200);
    }
    return http.StreamedResponse(const Stream.empty(), 404);
  }));
}

TrackChange _track(int id, String path, {bool transcode = false, int? size}) =>
    TrackChange(trackId: id, relativePath: path, transcode: transcode, size: size);

void main() {
  late Directory card;

  setUp(() async {
    card = await Directory.systemTemp.createTemp('trobar-test-');
  });

  tearDown(() async {
    await card.delete(recursive: true);
  });

  test('downloads land under their relative path and ack real bytes', () async {
    final acks = <Map<String, dynamic>>[];
    final engine = SyncEngine(_client({1: List.filled(1234, 7)}, acks), card);

    final result = await engine.run(ChangeSet(
      toDownload: [_track(1, 'Artist/Album/01 - One.flac')],
      toDelete: const [],
      downloaded: const [],
    ));

    expect(result.downloadedCount, 1);
    expect(result.firstError, isNull);
    final f = File(p.join(card.path, 'Artist', 'Album', '01 - One.flac'));
    expect(await f.length(), 1234);
    expect(acks, [
      {'track_id': 1, 'status': 'downloaded', 'bytes_on_device': 1234}
    ]);
    // no stray .part left behind
    expect(
        card
            .listSync(recursive: true)
            .whereType<File>()
            .where((e) => e.path.endsWith('.part')),
        isEmpty);
  });

  test('transcode-flagged tracks are skipped, not acked (M2)', () async {
    final acks = <Map<String, dynamic>>[];
    final engine = SyncEngine(_client({}, acks), card);

    final result = await engine.run(ChangeSet(
      toDownload: [_track(1, 'A/B/01 - X.mp3', transcode: true)],
      toDelete: const [],
      downloaded: const [],
    ));

    expect(result.skippedTranscode, 1);
    expect(result.downloadedCount, 0);
    expect(acks, isEmpty);
  });

  test('a failed download leaves no partial file and keeps syncing', () async {
    final acks = <Map<String, dynamic>>[];
    final engine =
        SyncEngine(_client({2: List.filled(10, 1)}, acks), card); // id 1 -> 404

    final result = await engine.run(ChangeSet(
      toDownload: [
        _track(1, 'A/B/01 - Fails.flac'),
        _track(2, 'A/B/02 - Works.flac'),
      ],
      toDelete: const [],
      downloaded: const [],
    ));

    expect(result.downloadedCount, 1);
    expect(result.firstError, contains('01 - Fails.flac'));
    expect(File(p.join(card.path, 'A', 'B', '01 - Fails.flac.part')).existsSync(),
        isFalse);
    expect(File(p.join(card.path, 'A', 'B', '02 - Works.flac')).existsSync(),
        isTrue);
  });

  test('deletes remove the file, prune empty dirs, and ack removed', () async {
    final f = File(p.join(card.path, 'A', 'B', '01 - Gone.flac'));
    await f.parent.create(recursive: true);
    await f.writeAsBytes([1, 2, 3]);
    final keeper = File(p.join(card.path, 'A', 'C', 'stays.flac'));
    await keeper.parent.create(recursive: true);
    await keeper.writeAsBytes([1]);

    final acks = <Map<String, dynamic>>[];
    final engine = SyncEngine(_client({}, acks), card);
    final result = await engine.run(ChangeSet(
      toDownload: const [],
      toDelete: [_track(9, 'A/B/01 - Gone.flac')],
      downloaded: const [],
    ));

    expect(result.deletedCount, 1);
    expect(f.existsSync(), isFalse);
    expect(f.parent.existsSync(), isFalse); // A/B pruned
    expect(keeper.existsSync(), isTrue); // A survives (A/C not empty)
    expect(acks, [
      {'track_id': 9, 'status': 'removed'}
    ]);
  });

  test('findMissing flags exactly the absent downloaded tracks', () async {
    final present = File(p.join(card.path, 'A', 'B', '01 - Here.flac'));
    await present.parent.create(recursive: true);
    await present.writeAsBytes([1]);

    final engine = SyncEngine(_client({}, []), card);
    final missing = await engine.findMissing(ChangeSet(
      toDownload: const [],
      toDelete: const [],
      downloaded: [
        _track(1, 'A/B/01 - Here.flac'),
        _track(2, 'A/B/02 - Lost.flac'),
      ],
    ));

    expect(missing.map((t) => t.trackId), [2]);
  });

  test('findOrphans flags unmanaged files, spares .trobar and expected ones',
      () async {
    for (final rel in [
      'A/B/01 - Kept.mp3', // expected (downloaded)
      'A/B/01 - Kept.flac', // old-extension leftover after a format change
      'C/random-note.txt', // user's own file
      '.trobar/device.json', // pairing config — never an orphan
    ]) {
      final f = File(p.joinAll([card.path, ...rel.split('/')]));
      await f.parent.create(recursive: true);
      await f.writeAsBytes([1]);
    }

    final engine = SyncEngine(_client({}, []), card);
    final orphans = await engine.findOrphans(ChangeSet(
      toDownload: const [],
      toDelete: const [],
      downloaded: [_track(1, 'A/B/01 - Kept.mp3')],
    ));

    expect(orphans, ['A/B/01 - Kept.flac', 'C/random-note.txt']);

    await engine.deleteOrphans(orphans);
    expect(File(p.join(card.path, 'A', 'B', '01 - Kept.mp3')).existsSync(),
        isTrue);
    expect(File(p.join(card.path, 'A', 'B', '01 - Kept.flac')).existsSync(),
        isFalse);
    expect(Directory(p.join(card.path, 'C')).existsSync(), isFalse); // pruned
    expect(File(p.join(card.path, '.trobar', 'device.json')).existsSync(),
        isTrue);
  });

  test('playlists: writes, updates, stale-deletes managed, spares foreign',
      () async {
    final acks = <Map<String, dynamic>>[];
    final engine = SyncEngine(_client({}, acks), card);
    const marker = SyncEngine.m3uMarker;

    // a stale Trobar playlist and a user-made playlist already on the card
    await File(p.join(card.path, 'Old Mix.m3u8'))
        .writeAsString('#EXTM3U\n$marker\nA/B/x.mp3\n');
    await File(p.join(card.path, 'My Own.m3u8'))
        .writeAsString('#EXTM3U\nA/B/y.mp3\n');

    const pl = PlaylistFile(
        name: 'Road Trip',
        filename: 'Road Trip.m3u8',
        content: '#EXTM3U\n$marker\n#PLAYLIST:Road Trip\nArt/Al/01 - One.mp3\n');
    final result = await engine.run(ChangeSet(
      toDownload: const [],
      toDelete: const [],
      downloaded: const [],
      playlists: const [pl],
    ));

    expect(result.playlistCount, 1);
    expect(await File(p.join(card.path, 'Road Trip.m3u8')).readAsString(),
        pl.content);
    expect(File(p.join(card.path, 'Old Mix.m3u8')).existsSync(), isFalse);
    expect(File(p.join(card.path, 'My Own.m3u8')).existsSync(), isTrue);

    // managed playlists are not orphans; foreign files still are
    final orphans = await engine.findOrphans(ChangeSet(
        toDownload: const [],
        toDelete: const [],
        downloaded: const [],
        playlists: const [pl]));
    expect(orphans, ['My Own.m3u8']);
  });

  test('artist images: honours device setting, size param, never overwrites',
      () async {
    for (final rel in ['Beck/Al/01 - x.mp3', 'Muse/Al/01 - y.mp3']) {
      final f = File(p.joinAll([card.path, ...rel.split('/')]));
      await f.parent.create(recursive: true);
      await f.writeAsBytes([1]);
    }
    // Muse already has a hand-placed picture
    await File(p.join(card.path, 'Muse', 'artist.jpg')).writeAsBytes([9, 9]);

    final requests = <Uri>[];
    final engine = SyncEngine(
        _client({}, [],
            artistImages: {'Beck': [7, 7, 7]}, imageRequests: requests),
        card,
        artistImages: 'small');
    await engine.run(const ChangeSet(
        toDownload: [], toDelete: [], downloaded: []));

    expect(await File(p.join(card.path, 'Beck', 'artist.jpg')).readAsBytes(),
        [7, 7, 7]);
    // hand-placed picture untouched, and no request was made for it
    expect(await File(p.join(card.path, 'Muse', 'artist.jpg')).readAsBytes(),
        [9, 9]);
    expect(requests.map((u) => u.queryParameters['artist']), ['Beck']);
    expect(requests.first.queryParameters['size'], 'small');

    // off (null) = no requests at all
    final requests2 = <Uri>[];
    await File(p.join(card.path, 'Beck', 'artist.jpg')).delete();
    final engineOff = SyncEngine(
        _client({}, [], imageRequests: requests2), card);
    await engineOff.run(const ChangeSet(
        toDownload: [], toDelete: [], downloaded: []));
    expect(requests2, isEmpty);
    expect(File(p.join(card.path, 'Beck', 'artist.jpg')).existsSync(), isFalse);
  });
}
