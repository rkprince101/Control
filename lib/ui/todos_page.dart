import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../data/habits.dart';
import '../data/todos.dart';
import '../main.dart';
import '../state/control_store.dart';
import 'control_page.dart';
import 'controls.dart';
import 'expressive_progress.dart';
import 'month_date_strip.dart';
import 'sheet.dart';
import 'theme.dart';
import 'widgets.dart';

/// Todos for a day: what is overdue, due, coming up, undated, and done.
///
/// A todo belongs to a day, and an unfinished one follows you forward as
/// overdue until it is done. The strip at the top moves between days; the
/// composer at the bottom adds todos one after another without closing.
class TodosPage extends StatefulWidget {
  const TodosPage({this.onComposingChanged, super.key});

  /// Told when the composer opens and closes, so the shell can put its
  /// action button away while the composer has the bottom of the screen.
  final ValueChanged<bool>? onComposingChanged;

  @override
  State<TodosPage> createState() => TodosPageState();
}

class TodosPageState extends State<TodosPage> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  bool _composing = false;
  String? _editingId;

  /// The day in view. Null follows today, so the page moves on at midnight.
  DateTime? _picked;

  /// Due date for the todo being written; null means no due date.
  DateTime? _dueDate;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  DateTime _today(ControlStore store) => dateOnly(store.wallNow());
  DateTime _viewDay(ControlStore store) => _picked ?? _today(store);

  /// Opens the composer for a new todo due on the day in view.
  void startAdding() {
    final store = StoreScope.of(context);
    setState(() {
      _editingId = null;
      _input.clear();
      _dueDate = _viewDay(store);
      _composing = true;
    });
    widget.onComposingChanged?.call(true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _startEditing(Todo todo) {
    setState(() {
      _editingId = todo.id;
      _dueDate = todo.date;
      _input.text = todo.title;
      _composing = true;
    });
    widget.onComposingChanged?.call(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _input.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _input.text.length,
      );
    });
  }

  void _stopComposing() {
    if (!_composing) return;
    setState(() {
      _composing = false;
      _editingId = null;
    });
    widget.onComposingChanged?.call(false);
    FocusScope.of(context).unfocus();
  }

  void _submit() {
    final store = StoreScope.of(context);
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final editing = _editingId;
    if (editing != null) {
      store.updateTodo(
        editing,
        title: text,
        date: _dueDate,
        clearDate: _dueDate == null,
      );
      _input.clear();
      _stopComposing();
      return;
    }
    store.addTodo(text, _dueDate);
    _input.clear();
    // Stays open, so a list can be typed in one go.
    _focus.requestFocus();
  }

  Future<void> _pickDueDate() async {
    final store = StoreScope.of(context);
    final today = _today(store);
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _viewDay(store),
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 5, 12, 31),
    );
    if (picked != null) setState(() => _dueDate = dateOnly(picked));
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final book = store.todoBook;
    final today = _today(store);
    final day = _viewDay(store);
    final progress = book.progressOn(day);

    final overdue = book.overdueBefore(day);
    final due = book.dueOn(day);
    final upcoming = book.upcomingAfter(day);
    final dateless = book.dateless();
    final completed = book.completedOn(day);
    final empty =
        overdue.isEmpty &&
        due.isEmpty &&
        upcoming.isEmpty &&
        dateless.isEmpty &&
        completed.isEmpty;

    return Column(
      children: [
        Expanded(
          // A tap on empty space puts the composer away; taps on rows and
          // buttons still reach them first.
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _composing ? _stopComposing : null,
            child: ControlPage(
              title: 'Get it done',
              eyebrow: 'TODOS',
              subtitle: 'Write it down, tick it off, and clear your head.',
              children: [
                _DayChip(day: day, today: today),
                const SizedBox(height: 12),
                MonthDateStrip(
                  selected: day,
                  today: today,
                  onSelect: (value) => setState(
                    () => _picked = value == today ? null : dateOnly(value),
                  ),
                ),
                const SizedBox(height: 16),
                if (progress.total > 0) ...[
                  _DayProgress(
                    label:
                        '${describeRelativeDay(context, day, today)} · '
                        '${progress.done} of ${progress.total} done',
                    fraction: progress.done / progress.total,
                  ),
                  const SizedBox(height: 16),
                ],
                if (empty)
                  _EmptyTodos(
                    day: describeRelativeDay(context, day, today),
                    onAdd: startAdding,
                  )
                else ...[
                  if (overdue.isNotEmpty)
                    _Section(
                      label: 'Overdue',
                      color: ControlColors.of(context).heavy,
                      todos: overdue,
                      book: book,
                      today: today,
                      style: _TileStyle.overdue,
                      onEdit: _startEditing,
                    ),
                  if (due.isNotEmpty)
                    _Section(
                      label: describeRelativeDay(context, day, today),
                      todos: due,
                      book: book,
                      today: today,
                      onEdit: _startEditing,
                    ),
                  if (upcoming.isNotEmpty)
                    _Section(
                      label: 'Upcoming',
                      todos: upcoming,
                      book: book,
                      today: today,
                      style: _TileStyle.upcoming,
                      onEdit: _startEditing,
                    ),
                  if (dateless.isNotEmpty)
                    _Section(
                      label: 'No due date',
                      todos: dateless,
                      book: book,
                      today: today,
                      onEdit: _startEditing,
                    ),
                  if (completed.isNotEmpty)
                    _Section(
                      label: 'Completed',
                      todos: completed,
                      book: book,
                      today: today,
                      onEdit: _startEditing,
                    ),
                ],
              ],
            ),
          ),
        ),
        if (_composing)
          _Composer(
            input: _input,
            focus: _focus,
            editing: _editingId != null,
            dueDate: _dueDate,
            today: today,
            onPickDate: _pickDueDate,
            onToggleNoDate: () {
              setState(
                () => _dueDate = _dueDate == null ? _viewDay(store) : null,
              );
              _focus.requestFocus();
            },
            onSubmit: _submit,
            onCancel: _stopComposing,
          ),
      ],
    );
  }
}

/// The day in words, over the strip.
class _DayChip extends StatelessWidget {
  const _DayChip({required this.day, required this.today});

  final DateTime day;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final full = MaterialLocalizations.of(context).formatMediumDate(day);
    final relative = describeRelativeDay(context, day, today);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 6, 12, 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: Shapes.field,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.today_rounded, size: 15, color: scheme.primary),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                relative == full ? full : '$relative · $full, ${day.year}',
                style: theme.textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How much of the day in view is done.
class _DayProgress extends StatelessWidget {
  const _DayProgress({required this.label, required this.fraction});

  final String label;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final value = fraction.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ),
            Text(
              '${(value * 100).round()}%',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.light,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ExpressiveProgress(
          value: value,
          height: 16,
          color: colors.light,
          semanticsLabel: 'Todos done',
        ),
      ],
    );
  }
}

class _EmptyTodos extends StatelessWidget {
  const _EmptyTodos({required this.day, required this.onAdd});

  final String day;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.checklist_rounded,
              size: 32,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No todos for ${day.toLowerCase()}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Write down the next small thing.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ControlColors.of(context).textMuted,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add a todo'),
          ),
        ],
      ),
    );
  }
}

enum _TileStyle { normal, overdue, upcoming }

/// A labelled group of todos in one rounded card.
class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.todos,
    required this.book,
    required this.today,
    required this.onEdit,
    this.style = _TileStyle.normal,
    this.color,
  });

  final String label;
  final List<Todo> todos;
  final TodoBook book;
  final DateTime today;
  final ValueChanged<Todo> onEdit;
  final _TileStyle style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: color ?? theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Material(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: Shapes.card,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < todos.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 56),
                  _TodoTile(
                    todo: todos[i],
                    book: book,
                    today: today,
                    style: style,
                    onEdit: () => onEdit(todos[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One todo: a checkbox, the title and when, its steps underneath. Tap for
/// the detail sheet; swipe left for edit and delete.
class _TodoTile extends StatelessWidget {
  const _TodoTile({
    required this.todo,
    required this.book,
    required this.today,
    required this.style,
    required this.onEdit,
  });

  final Todo todo;
  final TodoBook book;
  final DateTime today;
  final _TileStyle style;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ControlColors.of(context);
    final overdueColor = colors.heavy;
    final late = book.isCompletedLate(todo);
    final overdue = style == _TileStyle.overdue;

    final titleColor = todo.isDone
        ? (late ? overdueColor : colors.textMuted)
        : (overdue ? overdueColor : scheme.onSurface);
    final checkColor = todo.isDone
        ? (late ? overdueColor : colors.light)
        : (overdue ? overdueColor : colors.textMuted);

    return SwipeActions(
      onEdit: onEdit,
      onDelete: () => store.removeTodo(todo.id),
      editLabel: 'Edit ${todo.title}',
      deleteLabel: 'Delete ${todo.title}',
      child: Material(
        color: scheme.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => TodoDetailSheet.show(context, todo.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: todo.isDone
                          ? 'Mark ${todo.title} not done'
                          : 'Mark ${todo.title} done',
                      onPressed: () => store.toggleTodo(todo.id),
                      icon: Icon(
                        todo.isDone
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: checkColor,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              todo.title,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: titleColor,
                                decoration: todo.isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            if (!todo.isDone &&
                                todo.date != null &&
                                style != _TileStyle.normal)
                              Text(
                                'Due ${describeRelativeDay(context, todo.date!, today)}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: overdue
                                      ? overdueColor
                                      : colors.textMuted,
                                ),
                              ),
                            if (todo.isDone && todo.completedAt != null)
                              Text(
                                '${late ? 'Completed late' : 'Completed'}: '
                                '${_stamp(context, todo.completedAt!)}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: late ? overdueColor : colors.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (todo.hasSubTodos) ...[
                      const SizedBox(width: 8),
                      _StepsBadge(todo: todo),
                    ],
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: colors.textMuted.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),
            if (todo.hasSubTodos)
              // The steps sit indented under the todo, on a guide line, so
              // they read as its children.
              Padding(
                padding: const EdgeInsets.only(left: 27, bottom: 8),
                child: Container(
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(color: scheme.outlineVariant, width: 2),
                    ),
                  ),
                  child: Column(
                    children: [
                      for (final step in todo.subTodos)
                        _InlineStep(todo: todo, step: step),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Sep 23, 2026, 2:05 PM".
String _stamp(BuildContext context, DateTime moment) {
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatShortMonthDay(moment)}, ${moment.year}, '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(moment))}';
}

class _InlineStep extends StatelessWidget {
  const _InlineStep({required this.todo, required this.step});

  final Todo todo;
  final SubTodo step;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    return Semantics(
      checked: step.isDone,
      label: step.title,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => store.toggleSubTodo(todo.id, step.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 7, 16, 7),
            child: Row(
              children: [
                Icon(
                  step.isDone
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: step.isDone ? colors.light : colors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    step.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: step.isDone ? colors.textMuted : null,
                      decoration: step.isDone
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "2/3" with a checklist icon: how many steps are done.
class _StepsBadge extends StatelessWidget {
  const _StepsBadge({required this.todo});

  final Todo todo;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    final allDone = todo.subDoneCount == todo.subTotalCount;
    final color = allDone
        ? colors.light
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.checklist_rounded, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            '${todo.subDoneCount}/${todo.subTotalCount}',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// A row that slides left to show Edit and Delete behind it.
///
/// The same two actions are offered to screen readers as custom actions, since
/// a swipe is not something every user can make.
class SwipeActions extends StatefulWidget {
  const SwipeActions({
    required this.child,
    required this.onEdit,
    required this.onDelete,
    required this.editLabel,
    required this.deleteLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String editLabel;
  final String deleteLabel;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions> {
  static const _open = 116.0;
  double _offset = 0;
  bool _dragging = false;

  void _close() => setState(() {
    _dragging = false;
    _offset = 0;
  });

  void _settle() => setState(() {
    _dragging = false;
    _offset = _offset < -_open / 2 ? -_open : 0;
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = ControlColors.of(context);
    final isOpen = _offset != 0;
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: widget.editLabel): widget.onEdit,
        CustomSemanticsAction(label: widget.deleteLabel): widget.onDelete,
      },
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _RevealButton(
                      icon: Icons.edit_rounded,
                      color: scheme.primary,
                      tooltip: widget.editLabel,
                      onTap: () {
                        _close();
                        widget.onEdit();
                      },
                    ),
                    const SizedBox(width: 10),
                    _RevealButton(
                      icon: Icons.delete_outline_rounded,
                      color: colors.heavy,
                      tooltip: widget.deleteLabel,
                      onTap: () {
                        _close();
                        widget.onDelete();
                      },
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onHorizontalDragUpdate: (details) => setState(() {
                _dragging = true;
                _offset = (_offset + details.delta.dx).clamp(-_open, 0.0);
              }),
              onHorizontalDragEnd: (_) => _settle(),
              child: AnimatedContainer(
                duration: _dragging || MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(_offset, 0, 0),
                child: Stack(
                  children: [
                    widget.child,
                    // While open, a tap anywhere on the row just closes it.
                    if (isOpen)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _close,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevealButton extends StatelessWidget {
  const _RevealButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    style: IconButton.styleFrom(backgroundColor: color.withValues(alpha: 0.14)),
    onPressed: onTap,
    icon: Icon(icon, color: color, size: 20),
  );
}

/// The bar that writes a todo: when it is due, and what it is.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.input,
    required this.focus,
    required this.editing,
    required this.dueDate,
    required this.today,
    required this.onPickDate,
    required this.onToggleNoDate,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController input;
  final FocusNode focus;
  final bool editing;
  final DateTime? dueDate;
  final DateTime today;
  final VoidCallback onPickDate;
  final VoidCallback onToggleNoDate;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          12 + (keyboard > 0 ? 0 : MediaQuery.viewPaddingOf(context).bottom),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DueDateChips(
              dueDate: dueDate,
              today: today,
              onPickDate: onPickDate,
              onToggleNoDate: onToggleNoDate,
              trailing: editing
                  ? TextButton(onPressed: onCancel, child: const Text('Cancel'))
                  : null,
            ),
            const SizedBox(height: 8),
            _EntryRow(
              input: input,
              focus: focus,
              hint: editing ? 'Edit todo' : 'Add a todo',
              icon: editing ? Icons.check_rounded : Icons.arrow_upward_rounded,
              tooltip: editing ? 'Save todo' : 'Add todo',
              onSubmit: onSubmit,
            ),
          ],
        ),
      ),
    );
  }
}

/// A due-date chip that opens the calendar, and a "No due date" chip beside
/// it.
class DueDateChips extends StatelessWidget {
  const DueDateChips({
    required this.dueDate,
    required this.today,
    required this.onPickDate,
    required this.onToggleNoDate,
    this.trailing,
    super.key,
  });

  final DateTime? dueDate;
  final DateTime today;
  final VoidCallback onPickDate;
  final VoidCallback onToggleNoDate;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final date = dueDate;
    return Row(
      children: [
        Flexible(
          child: ControlChip(
            label: date == null
                ? 'Pick a date'
                : describeRelativeDay(context, date, today),
            icon: Icons.event_rounded,
            selected: date != null,
            onTap: onPickDate,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: ControlChip(
            label: 'No due date',
            icon: Icons.event_busy_rounded,
            selected: date == null,
            onTap: onToggleNoDate,
          ),
        ),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

/// A text field and the round button that sends it.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.input,
    required this.focus,
    required this.hint,
    required this.icon,
    required this.tooltip,
    required this.onSubmit,
  });

  final TextEditingController input;
  final FocusNode focus;
  final String hint;
  final IconData icon;
  final String tooltip;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: input,
            focusNode: focus,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              hintText: hint,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filled(
          tooltip: tooltip,
          onPressed: onSubmit,
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          icon: Icon(icon),
        ),
      ],
    );
  }
}

/// A todo in full: its title and date, and the steps it breaks into.
class TodoDetailSheet extends StatefulWidget {
  const TodoDetailSheet({required this.todoId, super.key});

  final String todoId;

  static Future<void> show(BuildContext context, String todoId) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ControlColors.of(context).background,
      builder: (_) => TodoDetailSheet(todoId: todoId),
    );
  }

  @override
  State<TodoDetailSheet> createState() => _TodoDetailSheetState();
}

class _TodoDetailSheetState extends State<TodoDetailSheet> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  String? _editingStepId;
  bool _editingTodo = false;
  DateTime? _todoDate;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _focusAndSelect() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _input.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _input.text.length,
      );
    });
  }

  void _editStep(SubTodo step) {
    setState(() {
      _editingTodo = false;
      _editingStepId = step.id;
      _input.text = step.title;
    });
    _focusAndSelect();
  }

  void _editTodo(Todo todo) {
    setState(() {
      _editingStepId = null;
      _editingTodo = true;
      _todoDate = todo.date;
      _input.text = todo.title;
    });
    _focusAndSelect();
  }

  void _cancel() {
    _input.clear();
    setState(() {
      _editingTodo = false;
      _editingStepId = null;
    });
    FocusScope.of(context).unfocus();
  }

  /// Saves the todo, saves a step, or adds a step, by mode.
  void _submit(ControlStore store) {
    final text = _input.text.trim();
    if (_editingTodo) {
      if (text.isNotEmpty) {
        store.updateTodo(
          widget.todoId,
          title: text,
          date: _todoDate,
          clearDate: _todoDate == null,
        );
      }
      _cancel();
      return;
    }
    if (text.isEmpty) return;
    final step = _editingStepId;
    if (step != null) {
      store.updateSubTodo(widget.todoId, step, text);
      _cancel();
      return;
    }
    store.addSubTodo(widget.todoId, text);
    _input.clear();
    // Stays open for the next step.
    _focus.requestFocus();
  }

  Future<void> _pickTodoDate(DateTime today) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _todoDate ?? today,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 5, 12, 31),
    );
    if (picked != null) setState(() => _todoDate = dateOnly(picked));
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final todo = store.todoById(widget.todoId);
    if (todo == null) {
      // Deleted while open.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox(height: 120);
    }
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final today = dateOnly(store.wallNow());

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SheetScaffold(
        heightFactor: 0.85,
        title: 'Todo',
        leading: SheetAction('Close', onPressed: () => Navigator.pop(context)),
        trailing: SheetAction(
          'Edit',
          primary: true,
          onPressed: () => _editTodo(todo),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 20, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    tooltip: todo.isDone ? 'Mark not done' : 'Mark done',
                    onPressed: () => store.toggleTodo(todo.id),
                    icon: Icon(
                      todo.isDone
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 28,
                      color: todo.isDone ? colors.light : colors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            todo.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              decoration: todo.isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            todo.date == null
                                ? 'No due date'
                                : describeRelativeDay(
                                    context,
                                    todo.date!,
                                    today,
                                  ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (todo.hasSubTodos)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${todo.subDoneCount} of ${todo.subTotalCount} steps done',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ExpressiveProgress(
                      value: todo.subDoneCount / todo.subTotalCount,
                      height: 16,
                      color: colors.light,
                      semanticsLabel: 'Steps done',
                    ),
                  ],
                ),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: SectionLabel('Steps'),
            ),
            Expanded(
              child: todo.subTodos.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Break this todo into smaller steps.\nAdd one below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textMuted),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      children: [
                        Material(
                          color: theme.colorScheme.surfaceContainerLow,
                          borderRadius: Shapes.card,
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (
                                var i = 0;
                                i < todo.subTodos.length;
                                i++
                              ) ...[
                                if (i > 0) const Divider(height: 1, indent: 52),
                                _StepTile(
                                  todoId: todo.id,
                                  step: todo.subTodos[i],
                                  onEdit: () => _editStep(todo.subTodos[i]),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            Material(
              color: theme.colorScheme.surfaceContainerLow,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_editingTodo) ...[
                        DueDateChips(
                          dueDate: _todoDate,
                          today: today,
                          onPickDate: () => _pickTodoDate(today),
                          onToggleNoDate: () {
                            setState(
                              () =>
                                  _todoDate = _todoDate == null ? today : null,
                            );
                            _focus.requestFocus();
                          },
                          trailing: TextButton(
                            onPressed: _cancel,
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ] else if (_editingStepId != null) ...[
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton(
                            onPressed: _cancel,
                            child: const Text('Cancel'),
                          ),
                        ),
                      ],
                      _EntryRow(
                        input: _input,
                        focus: _focus,
                        hint: _editingTodo
                            ? 'Edit todo'
                            : _editingStepId != null
                            ? 'Edit step'
                            : 'Add a step',
                        icon: _editingTodo || _editingStepId != null
                            ? Icons.check_rounded
                            : Icons.add_rounded,
                        tooltip: _editingTodo
                            ? 'Save todo'
                            : _editingStepId != null
                            ? 'Save step'
                            : 'Add step',
                        onSubmit: () => _submit(store),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.todoId,
    required this.step,
    required this.onEdit,
  });

  final String todoId;
  final SubTodo step;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    return SwipeActions(
      onEdit: onEdit,
      onDelete: () => store.removeSubTodo(todoId, step.id),
      editLabel: 'Edit ${step.title}',
      deleteLabel: 'Delete ${step.title}',
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        child: Semantics(
          checked: step.isDone,
          label: step.title,
          child: ExcludeSemantics(
            child: InkWell(
              onTap: () => store.toggleSubTodo(todoId, step.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Icon(
                      step.isDone
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 22,
                      color: step.isDone ? colors.light : colors.textMuted,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        step.title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: step.isDone ? colors.textMuted : null,
                          decoration: step.isDone
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
