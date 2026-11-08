// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// Home driven by the OS's volume events: an arrival probes only the drives
// named, a removal drops them without a probe, a rescan scans everything,
// and a slow safety poll runs beside them. Without events, or when they
// fail, Home polls every 8 s as before.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trobar_desktop/app_prefs.dart';
import 'package:trobar_desktop/l10n/gen/app_localizations.dart';
import 'package:trobar_desktop/main.dart';
import 'package:trobar_desktop/models.dart';
import 'package:trobar_desktop/volume_events.dart';

const _config = DeviceConfig(serverUrl: 'http://srv', token: 't0k');

void main() {
  late Directory root;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('trobar_volumes');
    await AppPrefs.load(file: File('${root.path}/prefs.json'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  late StreamController<VolumeEvent> events;
  late int fullScans;
  late List<List<String>> probed;
  late List<(Directory, DeviceConfig)> machine;

  Future<void> pump(WidgetTester tester, {bool withEvents = true}) async {
    events = StreamController<VolumeEvent>();
    fullScans = 0;
    probed = [];
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomeScreen(
        discover: () async {
          fullScans++;
          return machine;
        },
        discoverRoots: (roots) async {
          probed.add([for (final r in roots) r.path]);
          return [for (final c in machine) if (roots.any((r) => r.path == c.$1.path)) c];
        },
        volumeEvents: withEvents ? () => events.stream : null,
      ),
    ));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  }

  final e = Directory('E:\\');

  testWidgets('with events, no 8 s poll: only the 60 s safety one', (tester) async {
    machine = [];
    await pump(tester);
    expect(fullScans, 1); // the launch scan
    await tester.pump(fallbackPoll);
    expect(fullScans, 1);
    await tester.pump(safetyPoll - fallbackPoll);
    await settle(tester);
    expect(fullScans, 2);
    await finish(tester);
  });

  testWidgets('an arrival probes only the drives it names', (tester) async {
    machine = [];
    await pump(tester);
    machine = [(e, _config)];
    events.add(VolumeEvent(arrived: true, roots: [e]));
    await settle(tester);
    expect(probed, [['E:\\']]);
    expect(fullScans, 1); // no full scan for it
    expect(find.text('E:\\'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a drive not readable yet on arrival is looked at once more', (tester) async {
    machine = [];
    await pump(tester);
    events.add(VolumeEvent(arrived: true, roots: [e]));
    await settle(tester);
    expect(probed, [['E:\\']]); // read too early: nothing yet
    machine = [(e, _config)];
    await tester.pump(arrivalRetry);
    await settle(tester);
    expect(probed, [['E:\\'], ['E:\\']]);
    expect(fullScans, 1);
    expect(find.text('E:\\'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('two arrivals close together both stay listed', (tester) async {
    machine = [];
    await pump(tester);
    final f = Directory('F:\\');
    final slowE = Completer<List<(Directory, DeviceConfig)>>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomeScreen(
        discover: () async => [],
        discoverRoots: (roots) {
          calls++;
          if (roots.first.path == e.path) return slowE.future;
          return Future.value([(f, _config)]);
        },
        volumeEvents: () => events.stream,
      ),
    ));
    await tester.pump();
    events.add(VolumeEvent(arrived: true, roots: [e])); // its probe is slow
    await settle(tester);
    events.add(VolumeEvent(arrived: true, roots: [f])); // answered at once
    await settle(tester);
    expect(find.text('F:\\'), findsOneWidget);
    slowE.complete([(e, _config)]);
    await settle(tester);
    expect(calls, 2);
    expect(find.text('E:\\'), findsOneWidget);
    expect(find.text('F:\\'), findsOneWidget); // not dropped by E's late apply
    await finish(tester);
  });

  testWidgets('a removal drops its drives without probing anything', (tester) async {
    machine = [(e, _config)];
    await pump(tester);
    expect(find.text('E:\\'), findsOneWidget);
    events.add(VolumeEvent(arrived: false, roots: [e]));
    await settle(tester);
    expect(probed, isEmpty);
    expect(fullScans, 1);
    expect(find.text('E:\\'), findsNothing);
    await finish(tester);
  });

  testWidgets('a rescan event scans everything at once', (tester) async {
    machine = [];
    await pump(tester);
    final card = Directory('${root.path}/Card')..createSync();
    machine = [(card, _config)];
    events.add(const VolumeEvent.rescan());
    await settle(tester);
    expect(fullScans, 2);
    expect(find.text(card.path), findsOneWidget);
    await finish(tester);
  });

  testWidgets('events that fail fall back to the 8 s poll', (tester) async {
    machine = [];
    await pump(tester);
    events.addError(StateError('watch died'));
    await settle(tester);
    await tester.pump(fallbackPoll);
    await settle(tester);
    expect(fullScans, 2);
    await finish(tester);
  });

  testWidgets('and so do events that end', (tester) async {
    machine = [];
    await pump(tester);
    await events.close();
    await settle(tester);
    await tester.pump(fallbackPoll);
    await settle(tester);
    expect(fullScans, 2);
    await finish(tester);
  });

  testWidgets('without events, Home polls every 8 s as before', (tester) async {
    machine = [];
    await pump(tester, withEvents: false);
    await tester.pump(fallbackPoll);
    await settle(tester);
    expect(fullScans, 2);
    await finish(tester);
  });

  test('drive letters become drive roots', () {
    expect([for (final d in driveRoots('EF')) d.path], ['E:\\', 'F:\\']);
  });

  test('a new volume under a watched mount root is a rescan event', () async {
    final mounts = Directory('${root.path}/media')..createSync();
    final got = Completer<VolumeEvent>();
    final sub = watchRoots([mounts]).listen((ev) {
      if (!got.isCompleted) got.complete(ev);
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    Directory('${mounts.path}/CARD').createSync();
    final ev = await got.future.timeout(const Duration(seconds: 5));
    expect(ev.roots, isNull);
    await sub.cancel();
  });
}
