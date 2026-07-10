// SPDX-License-Identifier: GPL-3.0-or-later
// M3 coverage: engine behaviour around the transcode path (fake encoder),
// plus a real-ffmpeg integration test (skipped when ffmpeg is absent).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:trobar_desktop/api_client.dart';
import 'package:trobar_desktop/models.dart';
import 'package:trobar_desktop/sync_engine.dart';
import 'package:trobar_desktop/transcoder.dart';

const _config = DeviceConfig(serverUrl: 'http://srv', token: 't0k');

ApiClient _client(Map<int, List<int>> files, List<Map<String, dynamic>> acks) {
  return ApiClient(_config, httpClient: MockClient.streaming((req, body) async {
    if (req.url.path.startsWith('/api/device/file/')) {
      final content = files[int.parse(req.url.pathSegments.last)];
      if (content == null) {
        return http.StreamedResponse(const Stream.empty(), 404);
      }
      return http.StreamedResponse(Stream.value(content), 200);
    }
    if (req.url.path == '/api/device/ack') {
      acks.add(
          jsonDecode(await utf8.decodeStream(body)) as Map<String, dynamic>);
      return http.StreamedResponse(
          Stream.value(utf8.encode('{"status":"ok"}')), 200);
    }
    if (req.url.path == '/api/device/storage') {
      return http.StreamedResponse(
          Stream.value(utf8.encode('{"status":"ok"}')), 200);
    }
    return http.StreamedResponse(const Stream.empty(), 404);
  }));
}

class FakeTranscoder implements Transcoder {
  final List<int> output;
  final bool fail;
  String? lastFormat;
  FakeTranscoder({this.output = const [77, 80, 51], this.fail = false});

  @override
  Future<void> transcode(File src, File dest, String format) async {
    lastFormat = format;
    if (fail) throw TranscodeException('boom');
    // real inputs arrive as a downloaded temp file
    expect(await src.exists(), isTrue);
    await dest.writeAsBytes(output);
  }
}

TrackChange _track(int id, String path, {bool transcode = false}) =>
    TrackChange(trackId: id, relativePath: path, transcode: transcode);

void main() {
  late Directory card;

  setUp(() async {
    card = await Directory.systemTemp.createTemp('trobar-tc-test-');
  });

  tearDown(() async {
    await card.delete(recursive: true);
  });

  test('transcode path writes MP3 bytes and acks the transcoded size',
      () async {
    final acks = <Map<String, dynamic>>[];
    final fake = FakeTranscoder(output: List.filled(333, 9));
    final engine = SyncEngine(_client({1: List.filled(999, 5)}, acks), card,
        transcoder: fake, transcodeFormat: 'mp3_192');

    final result = await engine.run(ChangeSet(
      toDownload: [_track(1, 'A/B/01 - X.mp3', transcode: true)],
      toDelete: const [],
      downloaded: const [],
    ));

    expect(result.transcodedCount, 1);
    expect(result.skippedTranscode, 0);
    expect(result.firstError, isNull);
    final f = File(p.join(card.path, 'A', 'B', '01 - X.mp3'));
    // the card holds the transcoder's output, not the 999-byte original
    expect(await f.length(), 333);
    expect(acks, [
      {'track_id': 1, 'status': 'downloaded', 'bytes_on_device': 333}
    ]);
    // the device's format string travels through to the encoder
    expect(fake.lastFormat, 'mp3_192');
  });

  test('no transcoder: flagged tracks skip with a message, others sync',
      () async {
    final acks = <Map<String, dynamic>>[];
    final engine = SyncEngine(_client({2: List.filled(10, 1)}, acks), card);

    final result = await engine.run(ChangeSet(
      toDownload: [
        _track(1, 'A/B/01 - Flagged.mp3', transcode: true),
        _track(2, 'A/B/02 - Plain.mp3'),
      ],
      toDelete: const [],
      downloaded: const [],
    ));

    expect(result.skippedTranscode, 1);
    expect(result.downloadedCount, 1);
    expect(result.firstError, contains('ffmpeg not found'));
    expect(acks.map((a) => a['track_id']), [2]);
  });

  test('a failing transcode leaves no partial file and no ack', () async {
    final acks = <Map<String, dynamic>>[];
    final engine = SyncEngine(_client({1: List.filled(10, 1)}, acks), card,
        transcoder: FakeTranscoder(fail: true), transcodeFormat: 'mp3_320');

    final result = await engine.run(ChangeSet(
      toDownload: [_track(1, 'A/B/01 - X.mp3', transcode: true)],
      toDelete: const [],
      downloaded: const [],
    ));

    expect(result.transcodedCount, 0);
    expect(result.firstError, contains('boom'));
    expect(acks, isEmpty);
    expect(
        card.listSync(recursive: true).whereType<File>().toList(), isEmpty);
  });

  test('real ffmpeg: FLAC in, tagged MP3 out', () async {
    final ffmpeg = await FfmpegTranscoder.locate();
    if (ffmpeg == null) {
      markTestSkipped('ffmpeg not installed');
      return;
    }
    final tmp = await Directory.systemTemp.createTemp('trobar-ffmpeg-');
    addTearDown(() => tmp.delete(recursive: true));

    // 1s sine-wave FLAC with a title tag, generated by the same ffmpeg
    final src = File(p.join(tmp.path, 'in.flac'));
    final gen = await Process.run(ffmpeg.binary, [
      '-hide_banner', '-loglevel', 'error', '-y',
      '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1',
      '-metadata', 'title=Test Tone', '-metadata', 'artist=Trobar',
      src.path,
    ]);
    expect(gen.exitCode, 0, reason: gen.stderr as String);

    final dest = File(p.join(tmp.path, 'out.part'));
    await ffmpeg.transcode(src, dest, 'mp3_128');

    final bytes = await dest.readAsBytes();
    expect(bytes.length, greaterThan(1000));
    // ID3v2 header ("ID3") — proves ID3 tags landed in the MP3 container
    expect(String.fromCharCodes(bytes.take(3)), 'ID3');
    // and the title survived the -map_metadata carry-over
    expect(String.fromCharCodes(bytes.take(512)), contains('Test Tone'));
  });

  test('the changes payload format beats the constructor value', () async {
    final acks = <Map<String, dynamic>>[];
    final fake = FakeTranscoder(output: List.filled(10, 1));
    // constructor says mp3_320 (stale device info); payload says mp3_128
    final engine = SyncEngine(_client({1: List.filled(99, 5)}, acks), card,
        transcoder: fake, transcodeFormat: 'mp3_320');

    await engine.run(const ChangeSet(
      toDownload: [
        TrackChange(trackId: 1, relativePath: 'A/B/01 - X.mp3', transcode: true)
      ],
      toDelete: [],
      downloaded: [],
      transcodeFormat: 'mp3_128',
    ));

    expect(fake.lastFormat, 'mp3_128');
  });
}
