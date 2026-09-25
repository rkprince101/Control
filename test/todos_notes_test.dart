import 'dart:io';

import 'package:control/data/notes.dart';
import 'package:control/data/todos.dart';
import 'package:control/state/control_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wednesday 23 September 2026.
final _today = DateTime(2026, 9, 23);
DateTime _day(int offset) =>
    DateTime(_today.year, _today.month, _today.day + offset);

Todo _todo(
  String id, {
  int? due,
  bool done = false,
  int? completed,
  List<SubTodo> steps = const [],
}) => Todo(
  id: id,
  title: id,
  date: due == null ? null : _day(due),
  isDone: done,
  completedAt: completed == null
      ? null
      : _day(completed).add(const Duration(hours: 10)),
  createdAt: _day(-30),
  subTodos: steps,
);

void main() {
  group('where a todo belongs on a day', () {
    final book = TodoBook([
      _todo('late', due: -2),
      _todo('today', due: 0),
      _todo('soon', due: 3),
      _todo('someday'),
      _todo('done on time', due: 0, done: true, completed: 0),
      _todo('done late', due: -4, done: true, completed: 0),
      _todo('done yesterday', due: -1, done: true, completed: -1),
    ]);

    test('overdue, due, upcoming, undated and completed', () {
      List<String> ids(List<Todo> todos) => [for (final t in todos) t.id];
      expect(ids(book.overdueBefore(_today)), ['late']);
      expect(ids(book.dueOn(_today)), ['today']);
      expect(ids(book.upcomingAfter(_today)), ['soon']);
      expect(ids(book.dateless()), ['someday']);
      expect(ids(book.completedOn(_today)).toSet(), {
        'done on time',
        'done late',
      });
    });

    test('a todo finished after its due day is late', () {
      final late = book.todos.firstWhere((t) => t.id == 'done late');
      final onTime = book.todos.firstWhere((t) => t.id == 'done on time');
      expect(book.isCompletedLate(late), isTrue);
      expect(book.isCompletedLate(onTime), isFalse);
    });

    test('the badge counts today and what is overdue, not the future', () {
      expect(book.pendingCountFor(_today), 2);
      // Looking at next week, today's and the overdue ones carry over.
      expect(book.pendingCountFor(_day(7)), 3);
    });

    test('progress counts the day, steps weigh one each', () {
      // Overdue 1, due 1, undated 1, finished today 2: 2 of 5.
      expect(book.progressOn(_today), (done: 2, total: 5));
      final withSteps = TodoBook([
        _todo(
          'plan',
          due: 0,
          steps: const [
            SubTodo(id: 'a', title: 'a', isDone: true),
            SubTodo(id: 'b', title: 'b'),
            SubTodo(id: 'c', title: 'c'),
          ],
        ),
        _todo('call', due: 0),
      ]);
      expect(withSteps.progressOn(_today), (done: 1, total: 4));
      // Yesterday's finished work does not pad today.
      expect(book.progressOn(_day(-1)).total, isNot(0));
    });

    test('todos and notes survive a round trip through JSON', () {
      final todo = _todo(
        'trip',
        due: 2,
        steps: const [SubTodo(id: 's', title: 'pack', isDone: true)],
      );
      final back = Todo.fromJson(todo.toJson())!;
      expect(back.toJson(), todo.toJson());
      expect(Todo.fromJson({'title': 'no id'}), isNull);

      final note = Note(
        id: 'n',
        title: 'Ideas',
        preview: 'one  two',
        bodyDelta: '[{"insert":"one\\n"}]',
        pinned: true,
        createdAt: _day(-1),
        updatedAt: _today,
      );
      expect(Note.fromJson(note.toJson())!.toJson(), note.toJson());
    });

    test('notes sort pinned first, then newest edit', () {
      Note note(String id, {bool pinned = false, int edited = 0}) => Note(
        id: id,
        pinned: pinned,
        createdAt: _day(-10),
        updatedAt: _day(edited),
      );
      final sorted = sortNotes([
        note('old'),
        note('pinned', pinned: true, edited: -5),
        note('new', edited: 1),
      ]);
      expect([for (final n in sorted) n.id], ['pinned', 'new', 'old']);
    });
  });

  group('store', () {
    late Directory storage;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      storage = Directory.systemTemp.createTempSync('control_todos');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.control/enforcement'),
            (call) async => switch (call.method) {
              'isAccessibilityEnabled' => false,
              'hasUsageAccess' => false,
              'stepsStatus' => <String, Object?>{
                'granted': false,
                'available': false,
              },
              'protectionStatus' => <String, Object?>{
                'adminActive': false,
                'deviceOwner': false,
                'uninstallBlocked': false,
              },
              'shortcutCounts' => <String, Object?>{},
              _ => null,
            },
          );
    });

    tearDown(() => storage.deleteSync(recursive: true));

    ControlStore newStore() => ControlStore(storageDirectory: storage);

    test('steps drive the todo, and the todo drives its steps', () async {
      final store = newStore();
      await store.init();
      await store.addTodo('Move house', null);
      final id = store.todos.single.id;
      await store.addSubTodo(id, 'Boxes');
      await store.addSubTodo(id, 'Van');
      expect(store.todoById(id)!.subTotalCount, 2);

      // Every step done: the todo is done.
      for (final step in store.todoById(id)!.subTodos) {
        await store.toggleSubTodo(id, step.id);
      }
      expect(store.todoById(id)!.isDone, isTrue);
      expect(store.todoById(id)!.completedAt, isNotNull);

      // A new unfinished step reopens it.
      await store.addSubTodo(id, 'Keys');
      expect(store.todoById(id)!.isDone, isFalse);
      expect(store.todoById(id)!.completedAt, isNull);

      // Ticking the todo ticks every step.
      await store.toggleTodo(id);
      expect(store.todoById(id)!.subTodos.every((s) => s.isDone), isTrue);
      await store.toggleTodo(id);
      expect(store.todoById(id)!.subTodos.any((s) => s.isDone), isFalse);

      final keys = store.todoById(id)!.subTodos.last;
      await store.updateSubTodo(id, keys.id, 'Spare keys');
      expect(store.todoById(id)!.subTodos.last.title, 'Spare keys');
      await store.removeSubTodo(id, keys.id);
      expect(store.todoById(id)!.subTotalCount, 2);
      store.dispose();
    });

    test('edits, moves and deletes', () async {
      final store = newStore();
      await store.init();
      await store.addTodo('   ', null);
      expect(store.todos, isEmpty, reason: 'blank titles are ignored');
      await store.addTodo('Call the bank', DateTime(2026, 9, 25, 15, 30));
      final id = store.todos.single.id;
      expect(store.todoById(id)!.date, DateTime(2026, 9, 25));

      await store.updateTodo(id, title: 'Call the bank back', clearDate: true);
      expect(store.todoById(id)!.title, 'Call the bank back');
      expect(store.todoById(id)!.date, isNull);

      await store.removeTodo(id);
      expect(store.todos, isEmpty);
      store.dispose();
    });

    test(
      'todos and notes survive a restart; pinning keeps its place',
      () async {
        final first = newStore();
        await first.init();
        await first.addTodo('Water plants', DateTime(2026, 9, 23));
        final created = DateTime(2026, 9, 1);
        final note = Note(
          id: first.newNoteId(),
          title: 'Groceries',
          preview: 'eggs',
          createdAt: created,
          updatedAt: created,
        );
        await first.upsertNote(note);
        await first.toggleNotePin(note.id);
        expect(first.noteById(note.id)!.pinned, isTrue);
        expect(first.noteById(note.id)!.updatedAt, created);
        first.dispose();

        final second = newStore();
        await second.init();
        expect(second.todos.single.title, 'Water plants');
        expect(second.notes.single.title, 'Groceries');
        expect(second.notes.single.pinned, isTrue);

        await second.removeNote(note.id);
        expect(second.notes, isEmpty);
        second.dispose();
      },
    );
  });
}
