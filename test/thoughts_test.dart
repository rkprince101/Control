import 'dart:convert';
import 'dart:io';

import 'package:control/data/thoughts.dart';
import 'package:control/main.dart';
import 'package:control/state/control_store.dart';
import 'package:control/ui/thoughts_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> entry(
  String id,
  String text, {
  String packageName = '',
  String target = '',
  String label = '',
  String blockTitle = '',
  int doneAt = 0,
  bool blockedNow = false,
  String status = '',
  DateTime? at,
}) => {
  'json': jsonEncode({
    'id': id,
    'text': text,
    'createdAt': (at ?? DateTime.now()).millisecondsSinceEpoch,
    'packageName': packageName,
    'target': target,
    'label': label,
    'blockTitle': blockTitle,
    'doneAt': doneAt,
  }),
  'blockedNow': blockedNow,
  'status': status,
};

Map<String, Object?> _withField(
  Map<String, Object?> item,
  String id,
  String field,
  Object value,
) {
  final json = Map<String, Object?>.from(
    jsonDecode(item['json']! as String) as Map,
  );
  if (json['id'] != id) return item;
  json[field] = value;
  return {...item, 'json': jsonEncode(json)};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ParkedThought', () {
    test('reads an app thought with its status', () {
      final thought = ParkedThought.fromChannel(
        entry(
          'a',
          'Reply to Sam',
          packageName: 'video.app',
          target: 'video.app',
          label: 'Video',
          blockedNow: true,
          status: 'Complete your conditions to unlock.',
        ),
      )!;
      expect(thought.text, 'Reply to Sam');
      expect(thought.isSite, isFalse);
      expect(thought.isManual, isFalse);
      expect(thought.isReady, isFalse);
      expect(thought.status, 'Complete your conditions to unlock.');
    });

    test('tells a site from an app, and a note to self from both', () {
      final site = ParkedThought.fromChannel(
        entry('s', 'Read it', packageName: 'browser', target: 'news.example'),
      )!;
      expect(site.isSite, isTrue);
      final manual = ParkedThought.fromChannel(entry('m', 'Call the bank'))!;
      expect(manual.isManual, isTrue);
      expect(manual.isReady, isTrue);
    });

    test('a done thought is neither ready nor waiting', () {
      final done = ParkedThought.fromChannel(
        entry('d', 'Done thing', doneAt: 5),
      )!;
      expect(done.isDone, isTrue);
      expect(done.isReady, isFalse);
    });

    test('rejects anything malformed rather than throwing', () {
      expect(ParkedThought.fromChannel(null), isNull);
      expect(ParkedThought.fromChannel({'json': 'not json'}), isNull);
      expect(ParkedThought.fromChannel({'json': '{"id":"x"}'}), isNull);
      expect(ParkedThought.fromChannel({'json': 42}), isNull);
    });
  });

  group('Thoughts page', () {
    const channel = MethodChannel('dev.control/enforcement');
    late Directory storage;
    late ControlStore store;
    late List<MethodCall> calls;
    late List<Object?> stored;

    setUp(() {
      storage = Directory.systemTemp.createTempSync('control_thoughts');
      store = ControlStore(storageDirectory: storage);
      calls = [];
      stored = [
        entry(
          'ready',
          'Reply to Sam about Saturday',
          packageName: 'video.app',
          target: 'video.app',
          label: 'Video',
        ),
        entry(
          'waiting',
          'Check the train time',
          packageName: 'maps.app',
          target: 'maps.app',
          label: 'Maps',
          blockTitle: 'Evenings',
          blockedNow: true,
          status: 'Blocked by your recurring schedule.',
        ),
        entry('done', 'Call the bank', doneAt: 1000),
      ];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            final args = call.arguments is Map ? call.arguments as Map : {};
            // Behaves like the native store: changes stick.
            switch (call.method) {
              case 'setThoughtDone':
                stored = [
                  for (final item in stored.cast<Map<String, Object?>>())
                    _withField(
                      item,
                      args['id'] as String,
                      'doneAt',
                      args['done'] == true ? 1000 : 0,
                    ),
                ];
              case 'deleteThought':
                stored = [
                  for (final item in stored.cast<Map<String, Object?>>())
                    if (jsonDecode(item['json']! as String)['id'] != args['id'])
                      item,
                ];
              case 'restoreThought':
                stored = [
                  ...stored,
                  {'json': args['json'], 'blockedNow': false, 'status': ''},
                ];
            }
            return switch (call.method) {
              'thoughts' => stored,
              'openThoughtTarget' => true,
              _ => null,
            };
          });
    });

    tearDown(() {
      store.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      storage.deleteSync(recursive: true);
    });

    Future<void> host(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await store.refreshThoughts();
      await tester.pumpWidget(
        StoreScope(
          store: store,
          child: const MaterialApp(home: Scaffold(body: ThoughtsPage())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sorts thoughts into ready, still blocked and done', (
      tester,
    ) async {
      await host(tester);
      expect(find.text('READY NOW'), findsOneWidget);
      expect(find.text('STILL BLOCKED'), findsOneWidget);
      expect(find.text('DONE'), findsOneWidget);
      expect(find.text('Open Video'), findsOneWidget);
      // A blocked one says why, and offers no way in.
      expect(find.text('Open Maps'), findsNothing);
      expect(
        find.text('Waiting on Evenings. Blocked by your recurring schedule.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens the app a ready thought was about', (tester) async {
      await host(tester);
      await tester.tap(find.text('Open Video'));
      await tester.pumpAndSettle();
      final open = calls.lastWhere(
        (call) => call.method == 'openThoughtTarget',
      );
      expect((open.arguments as Map)['packageName'], 'video.app');
    });

    testWidgets('ticks a thought off at once', (tester) async {
      await host(tester);
      await tester.tap(find.byTooltip('Mark as done').first);
      await tester.pump();
      final call = calls.lastWhere((call) => call.method == 'setThoughtDone');
      expect(call.arguments, {'id': 'ready', 'done': true});
      expect(store.thoughts.firstWhere((t) => t.id == 'ready').isDone, isTrue);
    });

    testWidgets('a swipe deletes, and Undo puts it back as it was', (
      tester,
    ) async {
      await host(tester);
      final raw = store.thoughts.firstWhere((t) => t.id == 'ready').raw;
      await tester.drag(
        find.text('Reply to Sam about Saturday'),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();
      expect(calls.where((call) => call.method == 'deleteThought'), isNotEmpty);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      // Gone on its own afterwards too.
      expect(find.text('Thought deleted.'), findsNothing);
      final restore = calls.lastWhere(
        (call) => call.method == 'restoreThought',
      );
      expect((restore.arguments as Map)['json'], raw);
    });

    testWidgets('the undo offer goes away on its own', (tester) async {
      await host(tester);
      await tester.drag(
        find.text('Reply to Sam about Saturday'),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Thought deleted.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Thought deleted.'), findsNothing);
    });

    testWidgets('nothing parked explains where thoughts come from', (
      tester,
    ) async {
      stored = [];
      await host(tester);
      expect(find.text('Nothing parked'), findsOneWidget);
      expect(find.textContaining('Park a thought'), findsOneWidget);
    });

    testWidgets('a thought can be parked from inside Control', (tester) async {
      stored = [];
      await host(tester);
      ThoughtEditorSheet.show(tester.element(find.byType(ThoughtsPage)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  Book the dentist  ');
      await tester.pump();
      await tester.tap(find.text('Park it'));
      await tester.pumpAndSettle();
      final add = calls.lastWhere((call) => call.method == 'addThought');
      expect(add.arguments, {'text': 'Book the dentist'});
    });
  });
}
