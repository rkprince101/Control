/// A step under a [Todo]: a checklist item of its own.
class SubTodo {
  const SubTodo({required this.id, required this.title, this.isDone = false});

  final String id;
  final String title;
  final bool isDone;

  SubTodo copyWith({String? title, bool? isDone}) => SubTodo(
    id: id,
    title: title ?? this.title,
    isDone: isDone ?? this.isDone,
  );

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'isDone': isDone};

  static SubTodo? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String) return null;
    return SubTodo(id: id, title: title, isDone: json['isDone'] == true);
  }
}

/// A light, date-scoped to-do.
///
/// [date] is the day it is due, or null for "someday". A todo shows on its own
/// day and, while still undone, carries over to every later day as overdue.
/// [completedAt] is set when it is done and cleared when it is undone, and a
/// done todo lives on the day it was finished. With [subTodos], the todo is
/// done exactly when all of its steps are.
class Todo {
  Todo({
    required this.id,
    required this.title,
    required this.createdAt,
    this.isDone = false,
    this.date,
    this.completedAt,
    this.subTodos = const [],
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  final String title;
  final bool isDone;

  /// Date only. Null means no due date: never overdue, shown every day.
  final DateTime? date;
  final DateTime createdAt;
  final DateTime? completedAt;
  final List<SubTodo> subTodos;

  /// The last change of any kind.
  final DateTime updatedAt;

  bool get hasSubTodos => subTodos.isNotEmpty;
  int get subDoneCount => subTodos.where((step) => step.isDone).length;
  int get subTotalCount => subTodos.length;

  Todo copyWith({
    String? title,
    bool? isDone,
    DateTime? date,
    bool clearDate = false,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    List<SubTodo>? subTodos,
    DateTime? updatedAt,
  }) => Todo(
    id: id,
    title: title ?? this.title,
    isDone: isDone ?? this.isDone,
    date: clearDate ? null : (date ?? this.date),
    createdAt: createdAt,
    completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    subTodos: subTodos ?? this.subTodos,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'isDone': isDone,
    'date': date?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'subTodos': [for (final step in subTodos) step.toJson()],
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Null for anything that is not a todo, so one bad entry is dropped rather
  /// than taking the whole list with it.
  static Todo? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    final created = DateTime.tryParse('${json['createdAt']}');
    if (id is! String || title is! String || created == null) return null;
    DateTime? parse(Object? raw) =>
        raw is String ? DateTime.tryParse(raw) : null;
    return Todo(
      id: id,
      title: title,
      isDone: json['isDone'] == true,
      date: parse(json['date']),
      createdAt: created,
      completedAt: parse(json['completedAt']),
      updatedAt: parse(json['updatedAt']) ?? created,
      subTodos: [
        for (final raw in (json['subTodos'] as List?) ?? const [])
          ?SubTodo.fromJson(raw),
      ],
    );
  }
}

/// Where each todo belongs on a given day. Pure, so the rules can be tested
/// without a widget.
///
/// For the day being viewed a todo is:
///  * overdue: undone, due before it
///  * due: undone, due on it
///  * upcoming: undone, due after it
///  * no due date: undone, dateless, shown every day
///  * completed: finished on it, late ones marked
class TodoBook {
  const TodoBook(this.todos);

  final List<Todo> todos;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Undone, due before [date]. Oldest first.
  List<Todo> overdueBefore(DateTime date) {
    final day = _day(date);
    return todos
        .where(
          (t) => !t.isDone && t.date != null && _day(t.date!).isBefore(day),
        )
        .toList()
      ..sort((a, b) => a.date!.compareTo(b.date!));
  }

  /// Undone, due on [date]. Newest first.
  List<Todo> dueOn(DateTime date) =>
      todos
          .where((t) => !t.isDone && t.date != null && _sameDay(t.date!, date))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Undone, due after [date]. Soonest first.
  List<Todo> upcomingAfter(DateTime date) {
    final day = _day(date);
    return todos
        .where((t) => !t.isDone && t.date != null && _day(t.date!).isAfter(day))
        .toList()
      ..sort((a, b) => a.date!.compareTo(b.date!));
  }

  /// Undone, with no due date. Newest first.
  List<Todo> dateless() =>
      todos.where((t) => !t.isDone && t.date == null).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Finished on [date]. A done todo lives on the day it was finished, not
  /// the day it was due; one with no finish time falls back to its due day so
  /// it never vanishes from every list. Most recent first.
  List<Todo> completedOn(DateTime date) {
    DateTime? when(Todo t) => t.completedAt ?? t.date;
    return todos.where((t) {
      final at = when(t);
      return t.isDone && at != null && _sameDay(at, date);
    }).toList()..sort(
      (a, b) => (when(b) ?? b.createdAt).compareTo(when(a) ?? a.createdAt),
    );
  }

  /// Finished after the day it was due.
  bool isCompletedLate(Todo t) =>
      t.isDone &&
      t.date != null &&
      t.completedAt != null &&
      _day(t.completedAt!).isAfter(_day(t.date!));

  /// What is still open on [date]: its own undone todos and the overdue ones
  /// carried into it. The drawer badge.
  int pendingCountFor(DateTime date) =>
      dueOn(date).length + overdueBefore(date).length;

  /// Progress for [date]: overdue, due, dateless, and whatever was finished
  /// on it. Upcoming todos are not this day's work. A todo with steps counts
  /// each step, so a todo with four steps weighs four.
  ({int done, int total}) progressOn(DateTime date) {
    var done = 0;
    var total = 0;
    for (final t in [
      ...overdueBefore(date),
      ...dueOn(date),
      ...dateless(),
      ...completedOn(date),
    ]) {
      if (t.hasSubTodos) {
        total += t.subTotalCount;
        done += t.subDoneCount;
      } else {
        total += 1;
        if (t.isDone) done += 1;
      }
    }
    return (done: done, total: total);
  }

  bool get isEmpty => todos.isEmpty;
}
