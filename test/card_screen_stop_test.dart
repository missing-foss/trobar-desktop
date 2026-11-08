// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// desktop#26: leaving the card screen during a sync asks first and, if told
// to, stops the sync and leaves once it has wound down, instead of closing
// the HTTP client under a download; a Stop button stops it in place.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trobar_desktop/app_prefs.dart';
import 'package:trobar_desktop/card_store.dart';
import 'package:trobar_desktop/l10n/gen/app_localizations.dart';
import 'package:trobar_desktop/main.dart';
import 'package:trobar_desktop/models.dart';

const _config = DeviceConfig(serverUrl: 'http://srv', token: 't0k');

/// A server with one track to download, which trickles in a chunk every
/// 20 ms and never ends on its own: the sync stays running until stopped.
MockClient _slowServer() => MockClient.streaming((req, _) async {
      final path = req.url.path;
      if (path == '/api/device/info') {
        return http.StreamedResponse(
            Stream.value(utf8.encode('{"name": "Card"}')), 200);
      }
      if (path == '/api/device/changes') {
        return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({
              'to_download': [
                {'track_id': 1, 'relative_path': 'A/B/01 - T.flac', 'size': 1}
              ],
              'to_delete': [],
              'downloaded': [],
            }))),
            200);
      }
      if (path.startsWith('/api/device/file/')) {
        return http.StreamedResponse(
            Stream.periodic(const Duration(milliseconds: 20), (_) => [0]), 200);
      }
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
    });

/// A client that, like the real one, fails what is in flight and anything
/// sent later with "Client is already closed" once it is closed. A
/// MockClient's close() breaks nothing, so it can't show a client being
/// closed under a request.
class _ClosingClient extends http.BaseClient {
  final http.Client inner;
  final _closed = Completer<void>();
  _ClosingClient(this.inner);

  bool get isClosed => _closed.isCompleted;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (isClosed) {
      return Future.error(http.ClientException('Client is already closed'));
    }
    return Future.any([
      inner.send(request),
      _closed.future.then<http.StreamedResponse>(
          (_) => throw http.ClientException('Client is already closed')),
    ]);
  }

  @override
  void close() {
    if (!isClosed) _closed.complete();
  }
}

/// A server whose /changes answers only after [delay], with one track the
/// server believes is on the card and isn't, so a sync that carries on
/// would find it missing and ask about it.
http.Client _slowChanges(Duration delay) => _ClosingClient(MockClient((req) async {
      final path = req.url.path;
      if (path == '/api/device/info') return http.Response('{"name": "Card"}', 200);
      if (path == '/api/device/changes') {
        await Future<void>.delayed(delay);
        return http.Response(
            jsonEncode({
              'to_download': [],
              'to_delete': [],
              'downloaded': [
                {'track_id': 7, 'relative_path': 'A/B/07 - Gone.flac', 'size': 1}
              ],
            }),
            200);
      }
      return http.Response('{}', 200);
    }));

void main() {
  late Directory root;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('trobar_stop');
    await AppPrefs.load(file: File('${root.path}/prefs.json'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// Opens the card screen on top of a home page (so Back has somewhere to
  /// go) and starts a sync that keeps running.
  Future<AppLocalizations> startSync(WidgetTester tester,
      {http.Client? server, int afterTapMs = 150}) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = server ?? _slowServer();
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => CardScreen(
                            root: root, config: _config, client: client))),
                    child: const Text('open')))),
      ));
    });
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.sync));
      await Future<void>.delayed(Duration(milliseconds: afterTapMs));
    });
    await tester.pump();
    return AppLocalizations.of(tester.element(find.byType(CardScreen)));
  }

  /// Unmounts everything and runs out the fake clock: a request started on
  /// it (the reload after a sync) leaves its timeout timer pending.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  }

  /// pumpAndSettle never returns while a sync runs (its spinner animates):
  /// a dialog's or a route's transition, in fixed steps instead.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> realTime(WidgetTester tester, int ms) async {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump();
  }

  testWidgets('Back during a sync asks first; Keep syncing keeps it going',
      (tester) async {
    final l = await startSync(tester);
    expect(find.text(l.syncStop), findsOneWidget); // the control: it's running

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    await navigator.maybePop();
    await settle(tester);
    expect(find.text(l.leaveDuringSyncTitle), findsOneWidget);

    await tester.tap(find.text(l.keepSyncing));
    await settle(tester);
    await realTime(tester, 60);
    expect(find.byType(CardScreen), findsOneWidget);
    expect(find.text(l.syncStop), findsOneWidget);

    // Wind the sync down before the test ends.
    await tester.tap(find.text(l.syncStop));
    await realTime(tester, 200);
    await finish(tester);
  });

  testWidgets('Stop and leave stops the sync, then leaves', (tester) async {
    final l = await startSync(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    await navigator.maybePop();
    await settle(tester);
    await tester.tap(find.text(l.stopAndLeave));
    await tester.pump();
    await realTime(tester, 300);
    await settle(tester);

    expect(find.byType(CardScreen), findsNothing);
    final outcome = await tester.runAsync(() => readSyncOutcome(root));
    // Stopped, in words, rather than "Client is already closed".
    expect(outcome?.error, l.syncStopped(0));
    expect(root.listSync(recursive: true).where((e) => e.path.endsWith('.part')),
        isEmpty);
    await finish(tester);
  });

  testWidgets('Stop stops the sync in place and says so', (tester) async {
    final l = await startSync(tester);
    await tester.tap(find.text(l.syncStop));
    await tester.pump();
    expect(find.text(l.syncStopping), findsOneWidget);
    await realTime(tester, 300);

    expect(find.byType(CardScreen), findsOneWidget);
    expect(find.text(l.syncStop), findsNothing); // not syncing any more
    expect(find.text(l.syncStopped(0)), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
      'Stop and leave while /changes answers: no question, stopped, not '
      '"Client is already closed"', (tester) async {
    final l = await startSync(tester,
        server: _slowChanges(const Duration(milliseconds: 400)), afterTapMs: 50);
    expect(find.text(l.syncStop), findsOneWidget); // the control: /changes pending

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    await navigator.maybePop();
    await settle(tester);
    await tester.tap(find.text(l.stopAndLeave));
    // Run the fake clock first: a screen that left at once would finish
    // its route transition here and close the client while /changes is
    // still pending.
    await settle(tester);
    await realTime(tester, 600); // /changes answers in the meantime
    await settle(tester);

    expect(find.byType(AlertDialog), findsNothing); // no "tracks missing" prompt
    expect(find.byType(CardScreen), findsNothing);
    final outcome = await tester.runAsync(() => readSyncOutcome(root));
    expect(outcome?.error, l.syncStopped(0));
    await finish(tester);
  });
}
