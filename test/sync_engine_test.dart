// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// Engine-level tests against a fake HTTP layer and a temp-dir "card" —
// covers the sync contract: atomic writes, real-bytes ack, delete + empty-dir
// pruning, the missing-file spot check, and the #11 path-traversal guard.

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

/// A server that takes the device-playlists upload and records each body.
ApiClient _playlistServer(List<Map<String, dynamic>> uploads,
    {int status = 200, int unknown = 0}) {
  return ApiClient(_config, httpClient: MockClient((req) async {
    if (req.url.path == '/api/device/playlists') {
      uploads.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response(
          '{"playlists":1,"tracks":1,"matched":1,"unknown":$unknown}', status);
    }
    return http.Response('{"status":"ok"}', 200);
  }));
}

const _empty = ChangeSet(toDownload: [], toDelete: [], downloaded: []);

TrackChange _track(int id, String path, {int? size}) =>
    TrackChange(trackId: id, relativePath: path, size: size);

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

  test('a server-transcoded (.mp3) track is downloaded like any other',
      () async {
    // Transcoding is server-side now: the server serves the already-converted
    // bytes under an .mp3 path, so the client just downloads them (#15).
    final acks = <Map<String, dynamic>>[];
    final engine = SyncEngine(_client({1: List.filled(42, 3)}, acks), card);

    final result = await engine.run(ChangeSet(
      toDownload: [_track(1, 'A/B/01 - X.mp3')],
      toDelete: const [],
      downloaded: const [],
    ));

    expect(result.downloadedCount, 1);
    expect(await File(p.join(card.path, 'A', 'B', '01 - X.mp3')).length(), 42);
    expect(acks, [
      {'track_id': 1, 'status': 'downloaded', 'bytes_on_device': 42}
    ]);
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

  test(
      'collectManifestPaths lists only audio files, spares playlists, '
      'artist.jpg, .trobar and other non-audio files (#85)', () async {
    for (final rel in [
      'A/B/01 - One.flac',
      'A/B/02 - Two.mp3',
      'A/B/03 - Three.m4a',
      'A/B/04 - Four.aiff',
      'A/B/05 - Five.AIF', // extensions are matched case-insensitively
      'A/B/06 - Six.alac', // not a real extension: ALAC lives in .m4a
      'A/artist.jpg',
      'Road Trip.m3u8', // a playlist Trobar itself wrote — not audio
      'C/random-note.txt', // the user's own unrelated file
      '.trobar/device.json',
      '.trobar/provenance.json',
    ]) {
      final f = File(p.joinAll([card.path, ...rel.split('/')]));
      await f.parent.create(recursive: true);
      await f.writeAsBytes([1]);
    }

    final engine = SyncEngine(_client({}, []), card);
    final held = await engine.collectManifestPaths();

    expect(held, [
      'A/B/01 - One.flac',
      'A/B/02 - Two.mp3',
      'A/B/03 - Three.m4a',
      'A/B/04 - Four.aiff',
      'A/B/05 - Five.AIF',
    ]);
  });

  test('collectManifestPaths on a blank card returns an empty list',
      () async {
    final engine = SyncEngine(_client({}, []), card);
    expect(await engine.collectManifestPaths(), isEmpty);
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

    // Neither the managed playlist nor the user's own (uploaded as theirs,
    // #24) is an orphan; a foreign file that isn't a playlist still is.
    await File(p.join(card.path, 'notes.txt')).writeAsString('x');
    final orphans = await engine.findOrphans(ChangeSet(
        toDownload: const [],
        toDelete: const [],
        downloaded: const [],
        playlists: const [pl]));
    expect(orphans, ['notes.txt']);
  });

  test("the user's own playlists are never orphans, at the root or deeper (#24)",
      () async {
    final own = {
      'Mine.m3u8': '#EXTM3U\nA/B/01 - One.mp3\n',
      'Sub/Dir/Walk.m3u': 'A/B/02 - Two.mp3\n',
    };
    for (final e in own.entries) {
      final f = File(p.joinAll([card.path, ...e.key.split('/')]));
      await f.parent.create(recursive: true);
      await f.writeAsString(e.value);
    }
    // A Trobar playlist the server no longer sends is a leftover.
    final stale = File(p.join(card.path, 'Old Mix.m3u8'));
    await stale.writeAsString('#EXTM3U\n${SyncEngine.m3uMarker}\n#PLAYLIST:Old Mix\n');
    final engine = SyncEngine(_client({}, []), card);

    final orphans = await engine.findOrphans(_empty);

    expect(orphans, ['Old Mix.m3u8']);
    await engine.deleteOrphans(orphans);
    for (final rel in own.keys) {
      expect(File(p.joinAll([card.path, ...rel.split('/')])).existsSync(), isTrue,
          reason: rel);
    }
  });

  test('a playlist that cannot be read is not offered for deletion', () async {
    await File(p.join(card.path, 'Locked.m3u8')).writeAsString('x');
    final engine = SyncEngine(_client({}, []), card,
        readFile: (f) async => throw FileSystemException('denied', f.path));
    expect(await engine.findOrphans(_empty), isEmpty);
  });

  group('path-traversal guard (#11): server paths only write inside the root',
      () {
    // A file just OUTSIDE the card root; a crafted "../…" or absolute server
    // path resolves to it. Each test asserts it's never touched.
    File victimFile(String suffix) =>
        File(p.join(card.parent.path,
            'trobar-victim-${DateTime.now().microsecondsSinceEpoch}-$suffix'));

    test('a ".." download target is rejected; siblings still sync', () async {
      final victim = victimFile('dl.txt');
      await victim.writeAsString('original');
      addTearDown(() { if (victim.existsSync()) victim.deleteSync(); });

      final acks = <Map<String, dynamic>>[];
      final engine = SyncEngine(
          _client({1: utf8.encode('EVIL'), 2: List.filled(5, 1)}, acks), card);
      final result = await engine.run(ChangeSet(
        toDownload: [
          _track(1, '../${p.basename(victim.path)}'),
          _track(2, 'A/B/ok.flac'),
        ],
        toDelete: const [],
        downloaded: const [],
      ));

      expect(victim.readAsStringSync(), 'original'); // never overwritten
      expect(result.downloadedCount, 1); // only the in-root track
      expect(result.firstError, isNotNull); // surfaced
      expect(File(p.join(card.path, 'A', 'B', 'ok.flac')).existsSync(), isTrue);
    });

    test('an absolute download target is rejected', () async {
      final victim = victimFile('abs.txt');
      addTearDown(() { if (victim.existsSync()) victim.deleteSync(); });

      final engine = SyncEngine(_client({1: utf8.encode('EVIL')}, []), card);
      final result = await engine.run(ChangeSet(
        toDownload: [_track(1, victim.path)], // absolute path
        toDelete: const [],
        downloaded: const [],
      ));

      expect(victim.existsSync(), isFalse); // never created
      expect(result.downloadedCount, 0);
      expect(result.firstError, isNotNull);
    });

    test('a ".." playlist filename is skipped; good playlists still write',
        () async {
      final victim = victimFile('pl.m3u8');
      addTearDown(() { if (victim.existsSync()) victim.deleteSync(); });

      final engine = SyncEngine(_client({}, []), card);
      final good = const PlaylistFile(
          name: 'Good', filename: 'Good.m3u8', content: '#EXTM3U\n');
      final evil = PlaylistFile(
          name: 'Evil',
          filename: '../${p.basename(victim.path)}',
          content: 'EVIL');
      final result = await engine.run(ChangeSet(
        toDownload: const [],
        toDelete: const [],
        downloaded: const [],
        playlists: [evil, good],
      ));

      expect(victim.existsSync(), isFalse); // not written outside root
      expect(File(p.join(card.path, 'Good.m3u8')).existsSync(), isTrue);
      expect(result.playlistCount, 1); // only the safe one counted
    });

    test('a ".." delete target cannot remove a file outside the root',
        () async {
      final victim = victimFile('del.txt');
      await victim.writeAsString('keep me');
      addTearDown(() { if (victim.existsSync()) victim.deleteSync(); });

      final engine = SyncEngine(_client({}, []), card);
      final result = await engine.run(ChangeSet(
        toDownload: const [],
        toDelete: [_track(9, '../${p.basename(victim.path)}')],
        downloaded: const [],
      ));

      expect(victim.existsSync(), isTrue); // untouched
      expect(result.deletedCount, 0);
      expect(result.firstError, isNotNull);
    });

    test('a plain in-root path is unaffected by the guard', () async {
      final acks = <Map<String, dynamic>>[];
      final engine = SyncEngine(_client({1: List.filled(3, 9)}, acks), card);
      final result = await engine.run(ChangeSet(
        toDownload: [_track(1, 'Artist/Album/01 - Fine.flac')],
        toDelete: const [],
        downloaded: const [],
      ));
      expect(result.downloadedCount, 1);
      expect(result.firstError, isNull);
      expect(
          File(p.join(card.path, 'Artist', 'Album', '01 - Fine.flac'))
              .existsSync(),
          isTrue);
    });
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

  test('a failed playlist write reports the actual error', () async {
    // A directory where the playlist file should go makes the write fail.
    await Directory(p.join(card.path, 'Road Trip.m3u8')).create();
    const pl = PlaylistFile(
        name: 'Road Trip', filename: 'Road Trip.m3u8', content: '#EXTM3U\n');
    final result = await SyncEngine(_playlistServer([]), card).run(const ChangeSet(
        toDownload: [], toDelete: [], downloaded: [], playlists: [pl]));
    expect(result.firstError, startsWith('playlists: '));
    expect(result.firstError, isNot(contains(r'$e')));
    expect(result.firstError, contains('Road Trip.m3u8'));
  });

  group('playlists made on the device', () {
    const marker = SyncEngine.m3uMarker;
    Future<void> put(String rel, String text) async {
      final f = File(p.join(card.path, rel));
      await f.parent.create(recursive: true);
      await f.writeAsString(text);
    }

    test('are collected anywhere on the card, Trobar\'s own and .trobar/ left out',
        () async {
      await put('Road Trip.m3u8', '#EXTM3U\n#EXTINF:20,A - T\nA/B/01 - T.flac\n\n');
      await put('Playlists/Gym.m3u', 'A/B/02 - U.mp3\r\n../A/B/03 - V.mp3\r\n');
      await put('Mix.m3u8', '#EXTM3U\n$marker\n#PLAYLIST:Mix\nA/B/x.mp3\n');
      await put('.trobar/cache.m3u', 'A/B/x.mp3\n');
      await put('Later.m3u', '#EXTM3U\n#PLAYLIST:x\n$marker\nA/B/y.mp3\n');
      await put('notes.txt', 'A/B/z.mp3\n');
      final found = await SyncEngine(_playlistServer([]), card).collectUserPlaylists();
      expect({for (final pl in found) pl.path: pl.entries}, {
        'Later.m3u': ['A/B/y.mp3'], // the marker counts on line 2 only
        'Playlists/Gym.m3u': ['A/B/02 - U.mp3', '../A/B/03 - V.mp3'],
        'Road Trip.m3u8': ['A/B/01 - T.flac'],
      });
    });

    test('dot-files and hidden folders are left out (macOS ._ files)', () async {
      await put('Playlists/Gym.m3u', 'A/B/01 - T.flac\n');
      // An AppleDouble header: binary, then whatever the resource fork held.
      await File(p.join(card.path, 'Playlists', '._Gym.m3u'))
          .writeAsBytes([0, 5, 22, 7, 0, 2, 0, 0, ...utf8.encode('Mac OS X        \nA/B/x\nC/D/y\n')]);
      await put('.Trashes/501/Old.m3u', 'A/B/z.flac\n');
      final found = await SyncEngine(_playlistServer([]), card).collectUserPlaylists();
      expect(found.map((pl) => pl.path), ['Playlists/Gym.m3u']);
    });

    test('an unreadable playlist file means nothing is sent this sync', () async {
      await put('Road Trip.m3u8', 'A/B/01 - T.flac\n');
      await put('Locked.m3u', 'A/B/02 - U.flac\n');
      // Fails for root too (CI runs as root, which reads a mode-000 file).
      Future<List<int>> reader(File f) => p.basename(f.path) == 'Locked.m3u'
          ? throw FileSystemException('Permission denied', f.path)
          : f.readAsBytes();
      final uploads = <Map<String, dynamic>>[];
      final result = await SyncEngine(_playlistServer(uploads), card, readFile: reader).run(_empty);
      expect(uploads, isEmpty, reason: 'a partial set would delete Locked on the server');
      expect(result.devicePlaylistCount, 0);
      expect(result.firstError, contains('Locked.m3u'));
    });

    test('a BOM is ignored and a Latin-1 file is read as Latin-1', () async {
      await put('bom.m3u8', '\uFEFF#EXTM3U\n$marker\nA/B/x.mp3\n');
      await put('bare.m3u', '\uFEFFA/B/01 - T.flac\n');
      await File(p.join(card.path, 'old.m3u'))
          .writeAsBytes(latin1.encode('Bj\u00f6rk/Homogenic/01 - Hunter.mp3\n'));
      final found = await SyncEngine(_playlistServer([]), card).collectUserPlaylists();
      expect({for (final pl in found) pl.path: pl.entries}, {
        'bare.m3u': ['A/B/01 - T.flac'], // no BOM left on the first entry
        'old.m3u': ['Bj\u00f6rk/Homogenic/01 - Hunter.mp3'],
      });
    });

    test('every sync uploads them, the whole set', () async {
      await put('Road Trip.m3u8', 'A/B/01 - T.flac\n');
      final uploads = <Map<String, dynamic>>[];
      final result = await SyncEngine(_playlistServer(uploads), card).run(_empty);
      expect(result.devicePlaylistCount, 1);
      expect(result.firstError, isNull);
      expect(uploads, [
        {'playlists': [{'path': 'Road Trip.m3u8', 'entries': ['A/B/01 - T.flac']}]}
      ]);
      // An empty card still uploads: that is how a deleted playlist is removed.
      await File(p.join(card.path, 'Road Trip.m3u8')).delete();
      await SyncEngine(_playlistServer(uploads), card).run(_empty);
      expect(uploads.last, {'playlists': []});
    });

    test('what the server could not match is kept for the summary', () async {
      await put('Road Trip.m3u8', 'A/B/01 - T.flac\nNobody/None/01 - X.mp3\n');
      final result = await SyncEngine(_playlistServer([], unknown: 1), card).run(_empty);
      expect(result.devicePlaylistCount, 1);
      expect(result.deviceUnknownEntries, 1);
    });

    test('a server without the endpoint (404) is not an error', () async {
      await put('Road Trip.m3u8', 'A/B/01 - T.flac\n');
      final result = await SyncEngine(_playlistServer([], status: 404), card).run(_empty);
      expect(result.devicePlaylistCount, 0);
      expect(result.firstError, isNull);
    });

    test('another failure is reported without failing the sync', () async {
      final result = await SyncEngine(_playlistServer([], status: 500), card).run(_empty);
      expect(result.firstError, contains('device playlists'));
      expect(result.firstError, contains('500'));
    });

    test('a person\'s playlist is never overwritten by a Trobar one of the same name',
        () async {
      await put('Road Trip.m3u8', '#EXTM3U\nmine/a.mp3\n');
      const pl = PlaylistFile(
          name: 'Road Trip',
          filename: 'Road Trip.m3u8',
          content: '#EXTM3U\n$marker\n#PLAYLIST:Road Trip\nArt/Al/01 - One.mp3\n');
      await SyncEngine(_playlistServer([]), card).run(const ChangeSet(
          toDownload: [], toDelete: [], downloaded: [], playlists: [pl]));
      expect(await File(p.join(card.path, 'Road Trip.m3u8')).readAsString(),
          '#EXTM3U\nmine/a.mp3\n');
    });
  });
}
