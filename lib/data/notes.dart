/// A free-form note, Apple Notes style.
///
/// The body is rich text, stored as a Quill Delta (its ops list, JSON-encoded
/// into [bodyDelta]). [title] and [preview] are plain text taken from it when
/// saved, so the list never has to decode a Delta to draw a row.
class Note {
  const Note({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.title = '',
    this.preview = '',
    this.bodyDelta = '',
    this.pinned = false,
  });

  final String id;
  final String title;
  final String preview;

  /// Quill Delta ops as JSON. Empty for a blank note.
  final String bodyDelta;
  final bool pinned;
  final DateTime createdAt;

  /// The last edit to the words. Pinning does not count.
  final DateTime updatedAt;

  /// No visible text: such a note is discarded rather than kept.
  bool get isBlank => title.trim().isEmpty && preview.trim().isEmpty;

  Note copyWith({
    String? title,
    String? preview,
    String? bodyDelta,
    bool? pinned,
    DateTime? updatedAt,
  }) => Note(
    id: id,
    title: title ?? this.title,
    preview: preview ?? this.preview,
    bodyDelta: bodyDelta ?? this.bodyDelta,
    pinned: pinned ?? this.pinned,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'preview': preview,
    'body': bodyDelta,
    'pinned': pinned,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  static Note? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final created = DateTime.tryParse('${json['createdAt']}');
    if (id is! String || created == null) return null;
    return Note(
      id: id,
      title: json['title'] as String? ?? '',
      preview: json['preview'] as String? ?? '',
      bodyDelta: json['body'] as String? ?? '',
      pinned: json['pinned'] == true,
      createdAt: created,
      updatedAt: DateTime.tryParse('${json['updatedAt']}') ?? created,
    );
  }
}

/// Pinned first, then the most recently edited.
List<Note> sortNotes(Iterable<Note> notes) => [...notes]
  ..sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    return b.updatedAt.compareTo(a.updatedAt);
  });
