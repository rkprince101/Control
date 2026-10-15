import 'package:flutter/material.dart';

import '../data/thoughts.dart';
import '../main.dart';
import '../state/control_store.dart';
import 'app_icons.dart';
import 'control_page.dart';
import 'sheet.dart';
import 'theme.dart';
import 'widgets.dart';

/// What the user reached for while it was blocked, kept for when it opens.
///
/// Thoughts are parked from the block screen. Here they wait in three piles:
/// ready (the app or site is open again, so go and do it), still blocked
/// (with what the block screen says about when), and done.
class ThoughtsPage extends StatelessWidget {
  const ThoughtsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final ready = store.thoughts.where((thought) => thought.isReady).toList();
    final waiting = store.thoughts
        .where((thought) => !thought.isDone && thought.blockedNow)
        .toList();
    final done = store.thoughts.where((thought) => thought.isDone).toList()
      ..sort((a, b) => b.doneAt!.compareTo(a.doneAt!));

    return ControlPage(
      title: 'Parked thoughts',
      eyebrow: 'Later, not now',
      subtitle:
          'What you reached for while it was blocked, kept for when it '
          'opens again.',
      children: [
        if (store.thoughts.isEmpty) const _Empty(),
        if (ready.isNotEmpty) ...[
          const SectionLabel('Ready now'),
          for (final thought in ready) _ThoughtCard(thought: thought),
          const SizedBox(height: 16),
        ],
        if (waiting.isNotEmpty) ...[
          const SectionLabel('Still blocked'),
          for (final thought in waiting) _ThoughtCard(thought: thought),
          const SizedBox(height: 16),
        ],
        if (done.isNotEmpty) ...[
          Row(
            children: [
              const Expanded(child: SectionLabel('Done')),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextButton(
                  onPressed: store.clearDoneThoughts,
                  child: const Text('Clear done'),
                ),
              ),
            ],
          ),
          for (final thought in done) _ThoughtCard(thought: thought),
        ],
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    return ControlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded, color: colors.textMuted),
          const SizedBox(height: 12),
          Text('Nothing parked', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'When an app is blocked, tap Park a thought on the block screen '
            'and write down what you opened it for. It waits here, and moves '
            'to Ready now the moment the app opens again.',
            style: TextStyle(color: colors.textMuted, height: 1.45),
          ),
        ],
      ),
    );
  }
}

/// One thought: where it came from, the words, and what can be done now.
class _ThoughtCard extends StatelessWidget {
  const _ThoughtCard({required this.thought});

  final ParkedThought thought;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);
    final theme = Theme.of(context);
    final done = thought.isDone;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey('thought-${thought.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: AlignmentDirectional.centerEnd,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: Shapes.card,
          ),
          child: Icon(
            Icons.delete_outline_rounded,
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
        onDismissed: (_) => _delete(context, store),
        child: GestureDetector(
          onTap: () => ThoughtEditorSheet.show(context, existing: thought),
          behavior: HitTestBehavior.opaque,
          child: ControlCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Source(thought: thought),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            thought.isManual ? 'Note to self' : thought.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _when(
                              context,
                              thought.createdAt,
                              store.wallClock(),
                            ),
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: done ? 'Mark as not done' : 'Mark as done',
                      onPressed: () =>
                          store.setThoughtDone(thought.id, done: !done),
                      icon: Icon(
                        done
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: done ? colors.light : colors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    thought.text,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.4,
                      color: done ? colors.textMuted : null,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (!done && thought.blockedNow) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_clock_outlined,
                          size: 16,
                          color: colors.medium,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            [
                              if (thought.blockTitle.isNotEmpty)
                                'Waiting on ${thought.blockTitle}.',
                              if (thought.status.isNotEmpty) thought.status,
                            ].join(' '),
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (thought.isReady && !thought.isManual) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => _open(context, store),
                    icon: Icon(
                      thought.isSite
                          ? Icons.open_in_browser_rounded
                          : Icons.open_in_new_rounded,
                      size: 18,
                    ),
                    label: Text('Open ${thought.label}'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, ControlStore store) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final opened = await store.openThoughtTarget(thought);
    if (!opened) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not open ${thought.label}.')),
      );
    }
  }

  void _delete(BuildContext context, ControlStore store) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    store.deleteThought(thought);
    messenger?.showSnackBar(
      SnackBar(
        content: const Text('Thought deleted.'),
        // A snack bar with an action stays until tapped unless told
        // otherwise; an undo that never leaves covers the action button.
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => store.restoreThought(thought),
        ),
      ),
    );
  }

  /// "Today, 3:42 PM", "Yesterday, 9:05 AM", "Oct 12, 6:30 PM".
  static String _when(BuildContext context, DateTime moment, DateTime now) {
    final local = MaterialLocalizations.of(context);
    final time = local.formatTimeOfDay(
      TimeOfDay.fromDateTime(moment),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(moment.year, moment.month, moment.day);
    final days = today.difference(day).inDays;
    if (days == 0) return 'Today, $time';
    if (days == 1) return 'Yesterday, $time';
    return '${local.formatShortMonthDay(moment)}, $time';
  }
}

/// The app's own icon, a globe for a site, a pencil for a note to self.
class _Source extends StatelessWidget {
  const _Source({required this.thought});

  final ParkedThought thought;

  @override
  Widget build(BuildContext context) {
    if (!thought.isManual && !thought.isSite) {
      return AppIcon(id: thought.packageName, size: 36);
    }
    final colors = ControlColors.of(context);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colors.cardRaised,
        borderRadius: BorderRadius.circular(36 * 0.24),
      ),
      child: Icon(
        thought.isSite ? Icons.language_rounded : Icons.edit_note_rounded,
        size: 20,
        color: colors.textMuted,
      ),
    );
  }
}

/// Parks a thought from inside Control, or edits one already parked.
class ThoughtEditorSheet extends StatefulWidget {
  const ThoughtEditorSheet({this.existing, super.key});

  final ParkedThought? existing;

  static Future<void> show(BuildContext context, {ParkedThought? existing}) =>
      showControlSheet<void>(
        context,
        builder: (_) => ThoughtEditorSheet(existing: existing),
      );

  @override
  State<ThoughtEditorSheet> createState() => _ThoughtEditorSheetState();
}

class _ThoughtEditorSheetState extends State<ThoughtEditorSheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.existing?.text ?? '',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _valid => _text.text.trim().isNotEmpty;

  void _save() {
    final store = StoreScope.read(context);
    final existing = widget.existing;
    if (existing == null) {
      store.addThought(_text.text);
    } else {
      store.updateThought(existing.id, _text.text);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final colors = ControlColors.of(context);
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SheetScaffold(
        title: existing == null ? 'Park a thought' : 'Edit thought',
        leading: SheetAction('Cancel', onPressed: () => Navigator.pop(context)),
        trailing: SheetAction(
          existing == null ? 'Park it' : 'Save',
          primary: true,
          onPressed: _valid ? _save : null,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            24 + (insets > 0 ? 0 : MediaQuery.paddingOf(context).bottom),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (existing != null && !existing.isManual) ...[
                Text(
                  'Parked while ${existing.label} was blocked.',
                  style: TextStyle(color: colors.textMuted),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _text,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'What do you want to come back to?',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
