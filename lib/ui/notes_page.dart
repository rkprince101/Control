import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../data/habits.dart';
import '../data/notes.dart';
import '../main.dart';
import 'control_page.dart';
import 'dialogs.dart';
import 'note_editor.dart';
import 'theme.dart';
import 'widgets.dart';

/// Notes, Apple Notes style: searchable, pinned first, newest edits next.
///
/// Swipe a note right to pin or unpin it, left to delete it; tap to open the
/// editor. New notes come from the page's action button.
class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final query = _query.trim().toLowerCase();
    final all = store.notes;
    final shown = query.isEmpty
        ? all
        : all
              .where(
                (note) =>
                    note.title.toLowerCase().contains(query) ||
                    note.preview.toLowerCase().contains(query),
              )
              .toList();
    final pinned = shown.where((note) => note.pinned).toList();
    final others = shown.where((note) => !note.pinned).toList();
    final now = store.wallNow();

    return ControlPage(
      title: 'Keep in mind',
      eyebrow: 'NOTES',
      subtitle: 'Somewhere for thoughts, lists and plans.',
      children: [
        TextField(
          controller: _search,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Search notes',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 16),
        if (shown.isEmpty)
          _EmptyNotes(nothingYet: all.isEmpty)
        else ...[
          if (pinned.isNotEmpty) ...[
            const SectionLabel('Pinned'),
            for (final note in pinned) _NoteCard(note: note, now: now),
            const SizedBox(height: 12),
          ],
          if (others.isNotEmpty) ...[
            if (pinned.isNotEmpty) const SectionLabel('Notes'),
            for (final note in others) _NoteCard(note: note, now: now),
          ],
        ],
      ],
    );
  }
}

/// "2:05 PM" today, "Yesterday", a weekday this week, then "Sep 3".
String _noteDate(BuildContext context, DateTime moment, DateTime now) {
  final localizations = MaterialLocalizations.of(context);
  final days = dateOnly(now).difference(dateOnly(moment)).inDays;
  if (days <= 0) {
    return localizations.formatTimeOfDay(TimeOfDay.fromDateTime(moment));
  }
  if (days == 1) return 'Yesterday';
  if (days < 7) {
    return const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][moment.weekday - 1];
  }
  return localizations.formatShortMonthDay(moment);
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.now});

  final Note note;
  final DateTime now;

  Future<bool> _confirmDelete(BuildContext context) => confirmAction(
    context,
    icon: Icons.delete_outline_rounded,
    tone: DialogTone.danger,
    title: 'Delete note?',
    message: 'This note will be permanently deleted.',
    cancelLabel: 'Keep',
    confirmLabel: 'Delete',
  );

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ControlColors.of(context);
    // A body-only note is headed by its first words, not "New note".
    final hasTitle = note.title.trim().isNotEmpty;
    final heading = hasTitle
        ? note.title
        : (note.preview.isNotEmpty ? note.preview : 'New note');
    final showPreview = hasTitle && note.preview.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: note.pinned ? 'Unpin' : 'Pin'): () =>
              store.toggleNotePin(note.id),
          CustomSemanticsAction(label: 'Delete'): () async {
            if (await _confirmDelete(context)) store.removeNote(note.id);
          },
        },
        child: Dismissible(
          key: ValueKey(note.id),
          background: _SwipeBackground(
            color: scheme.primary,
            icon: note.pinned
                ? Icons.push_pin_outlined
                : Icons.push_pin_rounded,
            label: note.pinned ? 'Unpin' : 'Pin',
            atEnd: false,
          ),
          secondaryBackground: _SwipeBackground(
            color: colors.heavy,
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            atEnd: true,
          ),
          confirmDismiss: (direction) async {
            // Right pins and springs back; left asks, then deletes.
            if (direction == DismissDirection.startToEnd) {
              store.toggleNotePin(note.id);
              return false;
            }
            return _confirmDelete(context);
          },
          onDismissed: (_) => store.removeNote(note.id),
          child: Material(
            color: scheme.surfaceContainerLow,
            borderRadius: Shapes.card,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => NoteEditorScreen.open(context, note: note),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (note.pinned) ...[
                          Icon(
                            Icons.push_pin_rounded,
                            size: 14,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            heading,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    if (showPreview)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          note.preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.textMuted,
                            height: 1.3,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _noteDate(context, note.updatedAt, now),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.textMuted,
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

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.icon,
    required this.label,
    required this.atEnd,
  });

  final Color color;
  final IconData icon;
  final String label;
  final bool atEnd;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 22),
    alignment: atEnd
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: Shapes.card,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
        ),
      ],
    ),
  );
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes({required this.nothingYet});

  final bool nothingYet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
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
              nothingYet
                  ? Icons.sticky_note_2_outlined
                  : Icons.search_off_rounded,
              size: 32,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            nothingYet ? 'No notes yet' : 'No matching notes',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            nothingYet
                ? 'Tap New note to write your first one.'
                : 'Try a different search.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ControlColors.of(context).textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
