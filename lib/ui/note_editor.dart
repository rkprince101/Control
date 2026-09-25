import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../data/notes.dart';
import '../main.dart';
import '../state/control_store.dart';
import 'dialogs.dart';
import 'sheet.dart';

/// The note editor, full screen: a title line over a rich-text body, with a
/// formatting toolbar docked above the keyboard.
///
/// It saves as you type (after a short pause) and again on the way out, and a
/// note left with no words in it is discarded rather than kept.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({this.note, super.key});

  /// The note to edit, or null to write a new one.
  final Note? note;

  static Future<void> open(BuildContext context, {Note? note}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(note: note)),
    );
  }

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  /// Text colours on offer: the swatch, and the hex Quill stores.
  static const _textColours = <(Color, String, String)>[
    (Color(0xFFFF3B30), '#FF3B30', 'Red'),
    (Color(0xFFFF9500), '#FF9500', 'Orange'),
    (Color(0xFFFFCC00), '#FFCC00', 'Yellow'),
    (Color(0xFF34C759), '#34C759', 'Green'),
    (Color(0xFF30B0C7), '#30B0C7', 'Teal'),
    (Color(0xFF007AFF), '#007AFF', 'Blue'),
    (Color(0xFF5856D6), '#5856D6', 'Indigo'),
    (Color(0xFFAF52DE), '#AF52DE', 'Purple'),
    (Color(0xFFFF2D55), '#FF2D55', 'Pink'),
    (Color(0xFF8E8E93), '#8E8E93', 'Grey'),
  ];

  late final ControlStore _store;
  late final String _noteId;
  late final TextEditingController _title;
  late final QuillController _body;
  final _bodyFocus = FocusNode();
  final _scroll = ScrollController();
  Timer? _saveTimer;
  bool _pinned = false;

  /// The version last saved, or the note as it was opened: what a change is
  /// measured against.
  Note? _saved;

  @override
  void initState() {
    super.initState();
    _store = StoreScope.read(context);
    final note = widget.note;
    _noteId = note?.id ?? _store.newNoteId();
    _pinned = note?.pinned ?? false;
    _saved = note;
    _title = TextEditingController(text: note?.title ?? '')
      ..addListener(_changed);

    var document = Document();
    if (note != null && note.bodyDelta.isNotEmpty) {
      try {
        document = Document.fromJson(jsonDecode(note.bodyDelta) as List);
      } catch (_) {
        // An unreadable body opens empty rather than not at all.
      }
    }
    _body = QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
    )..addListener(_changed);
  }

  void _changed() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  /// Saves the note, or removes it if it has become empty.
  void _save() {
    _saveTimer?.cancel();
    final title = _title.text.trim();
    final plain = _body.document.toPlainText().trim();
    final base = _saved;
    if (title.isEmpty && plain.isEmpty) {
      if (_store.noteById(_noteId) != null) _store.removeNote(_noteId);
      _saved = null;
      return;
    }
    final delta = jsonEncode(_body.document.toDelta().toJson());
    final contentChanged =
        base == null || title != base.title || delta != base.bodyDelta;
    final pinChanged = base == null || _pinned != base.pinned;
    // Opened and closed, or only the cursor moved: nothing to write, and no
    // reason to move the note to the top of the list.
    if (!contentChanged && !pinChanged) return;
    final preview = plain
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(3)
        .join('  ');
    final now = _store.wallNow();
    final note = Note(
      id: _noteId,
      title: title,
      preview: preview,
      bodyDelta: delta,
      pinned: _pinned,
      createdAt: base?.createdAt ?? now,
      // Only a change to the words counts as an edit; a pin keeps its place.
      updatedAt: contentChanged ? now : base.updatedAt,
    );
    _store.upsertNote(note);
    _saved = note;
  }

  void _togglePin() {
    setState(() => _pinned = !_pinned);
    _save();
  }

  Future<void> _confirmDelete() async {
    final navigator = Navigator.of(context);
    final confirmed = await confirmAction(
      context,
      icon: Icons.delete_outline_rounded,
      tone: DialogTone.danger,
      title: 'Delete note?',
      message: 'This note will be permanently deleted.',
      cancelLabel: 'Keep',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    _saveTimer?.cancel();
    if (_store.noteById(_noteId) != null) _store.removeNote(_noteId);
    // Nothing left to save on the way out.
    _saved = null;
    _title.removeListener(_changed);
    _body.removeListener(_changed);
    _title.clear();
    navigator.pop();
  }

  Future<void> _pickTextColour() async {
    await showControlSheet<void>(
      context,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return SheetScaffold(
          title: 'Text colour',
          leading: SheetAction(
            'Close',
            onPressed: () => Navigator.pop(sheetContext),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final (colour, hex, name) in _textColours)
                    _Swatch(
                      label: name,
                      onTap: () {
                        _body.formatSelection(ColorAttribute(hex));
                        Navigator.pop(sheetContext);
                      },
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colour,
                          border: Border.all(
                            color: scheme.onSurface.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                    ),
                  _Swatch(
                    label: 'Default colour',
                    onTap: () {
                      _body.formatSelection(const ColorAttribute(null));
                      Navigator.pop(sheetContext);
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.outline),
                      ),
                      child: Icon(
                        Icons.format_color_reset_rounded,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _title
      ..removeListener(_changed)
      ..dispose();
    _body
      ..removeListener(_changed)
      ..dispose();
    _bodyFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    DefaultTextBlockStyle block(TextStyle? style, VerticalSpacing spacing) =>
        DefaultTextBlockStyle(
          (style ?? const TextStyle()).copyWith(color: scheme.onSurface),
          HorizontalSpacing.zero,
          spacing,
          VerticalSpacing.zero,
          null,
        );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Whatever was typed last is saved before leaving.
        _save();
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SheetHeader(
                  title: widget.note == null ? 'New note' : 'Note',
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton.filledTonal(
                        tooltip: _pinned ? 'Unpin' : 'Pin',
                        isSelected: _pinned,
                        onPressed: _togglePin,
                        icon: const Icon(Icons.push_pin_outlined, size: 20),
                        selectedIcon: const Icon(
                          Icons.push_pin_rounded,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        tooltip: 'Delete',
                        onPressed: _confirmDelete,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  // It saves as you type: this only closes.
                  trailing: SheetAction(
                    'Done',
                    primary: true,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
                child: TextField(
                  controller: _title,
                  autofocus: widget.note == null,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _bodyFocus.requestFocus(),
                  style: text.headlineMedium,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'Title',
                    hintStyle: text.headlineMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.32),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: QuillEditor.basic(
                  controller: _body,
                  focusNode: _bodyFocus,
                  scrollController: _scroll,
                  config: QuillEditorConfig(
                    placeholder: 'Start writing…',
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                    expands: true,
                    // A ticked checklist line is struck through and dimmed.
                    customStyleBuilder: (attribute) {
                      if (attribute.key == Attribute.list.key &&
                          attribute.value == Attribute.checked.value) {
                        return TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: scheme.onSurface.withValues(alpha: 0.45),
                        );
                      }
                      return const TextStyle();
                    },
                    customStyles: DefaultStyles(
                      paragraph: block(
                        text.bodyLarge?.copyWith(height: 1.5),
                        const VerticalSpacing(0, 10),
                      ),
                      h1: block(
                        text.headlineMedium?.copyWith(height: 1.3),
                        const VerticalSpacing(16, 8),
                      ),
                      h2: block(
                        text.headlineSmall?.copyWith(height: 1.3),
                        const VerticalSpacing(12, 6),
                      ),
                      h3: block(
                        text.titleLarge?.copyWith(height: 1.3),
                        const VerticalSpacing(10, 4),
                      ),
                    ),
                    // Round checklist boxes, Apple Notes style. Bullets,
                    // numbers and quotes keep the default leading.
                    // ignore: experimental_member_use
                    customLeadingBlockBuilder: (node, config) {
                      final attribute = config.attribute;
                      if (attribute != Attribute.checked &&
                          attribute != Attribute.unchecked) {
                        return null;
                      }
                      final bool checked = config.value;
                      final enabled = config.enabled ?? true;
                      final size = (config.lineSize ?? 18).toDouble();
                      return Semantics(
                        checked: checked,
                        button: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: enabled
                              ? () => config.onCheckboxTap(!checked)
                              : null,
                          child: Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: checked
                                  ? scheme.primary
                                  : Colors.transparent,
                              border: Border.all(
                                color: checked
                                    ? scheme.primary
                                    : scheme.onSurface.withValues(alpha: 0.45),
                                width: 2,
                              ),
                            ),
                            child: checked
                                ? Icon(
                                    Icons.check_rounded,
                                    size: size * 0.7,
                                    color: scheme.onPrimary,
                                  )
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // One row of formatting above the keyboard, docked on a tonal
              // surface rather than set off by a line.
              ColoredBox(
                color: scheme.surfaceContainer,
                child: SafeArea(
                  top: false,
                  child: QuillSimpleToolbar(
                    controller: _body,
                    config: QuillSimpleToolbarConfig(
                      multiRowsDisplay: false,
                      // Inline N / H1 / H2 / H3 rather than a dropdown, which
                      // would open down into the keyboard.
                      headerStyleType: HeaderStyleType.buttons,
                      showColorButton: false,
                      showBackgroundColorButton: false,
                      showFontFamily: false,
                      showFontSize: false,
                      showInlineCode: false,
                      showCodeBlock: false,
                      showQuote: false,
                      showIndent: false,
                      showLink: false,
                      showAlignmentButtons: false,
                      showSearchButton: false,
                      showSubscript: false,
                      showSuperscript: false,
                      showUndo: false,
                      showRedo: false,
                      showDividers: false,
                      customButtons: [
                        QuillToolbarCustomButtonOptions(
                          tooltip: 'Text colour',
                          icon: Icon(
                            Icons.format_color_text_rounded,
                            size: 22,
                            color: scheme.onSurfaceVariant,
                          ),
                          onPressed: _pickTextColour,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: ExcludeSemantics(
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: SizedBox(width: 48, height: 48, child: child),
      ),
    ),
  );
}
