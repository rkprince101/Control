import 'dart:convert';

/// Something the user meant to do in a blocked app, written down on the block
/// screen instead, to pick up once the app opens again.
///
/// Stored natively (the block screen writes them with Flutter asleep); this is
/// the copy the Thoughts page shows, with whether its app is still blocked.
class ParkedThought {
  const ParkedThought({
    required this.id,
    required this.text,
    required this.createdAt,
    this.packageName = '',
    this.target = '',
    this.label = '',
    this.blockTitle = '',
    this.doneAt,
    this.blockedNow = false,
    this.status = '',
    this.raw = '',
  });

  /// One entry from the bridge: the stored thought as JSON, plus its status.
  static ParkedThought? fromChannel(Object? entry) {
    if (entry is! Map) return null;
    final raw = entry['json'];
    if (raw is! String) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final id = decoded['id'];
    final text = decoded['text'];
    if (id is! String || text is! String || id.isEmpty || text.isEmpty) {
      return null;
    }
    final done = (decoded['doneAt'] as num?)?.toInt() ?? 0;
    return ParkedThought(
      id: id,
      text: text,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (decoded['createdAt'] as num?)?.toInt() ?? 0,
      ),
      packageName: decoded['packageName'] as String? ?? '',
      target: decoded['target'] as String? ?? '',
      label: decoded['label'] as String? ?? '',
      blockTitle: decoded['blockTitle'] as String? ?? '',
      doneAt: done > 0 ? DateTime.fromMillisecondsSinceEpoch(done) : null,
      blockedNow: entry['blockedNow'] as bool? ?? false,
      status: entry['status'] as String? ?? '',
      raw: raw,
    );
  }

  final String id;
  final String text;
  final DateTime createdAt;

  /// The app that was blocked: the browser, for a site.
  final String packageName;

  /// What the block was on: the package again, or the site's domain. Empty
  /// for a thought parked from inside Control.
  final String target;

  /// The app's name, or the site's domain.
  final String label;

  /// The block that was in the way.
  final String blockTitle;

  final DateTime? doneAt;

  /// The app or site is still behind a block right now.
  final bool blockedNow;

  /// What the block screen would say, while [blockedNow].
  final String status;

  /// The stored form, handed back untouched to undo a delete.
  final String raw;

  bool get isDone => doneAt != null;

  /// Parked from inside Control, about no app in particular.
  bool get isManual => target.isEmpty;

  bool get isSite => target.isNotEmpty && target != packageName;

  /// Open, and nothing stands between it and getting done.
  bool get isReady => !isDone && !blockedNow;

  @override
  bool operator ==(Object other) =>
      other is ParkedThought &&
      other.raw == raw &&
      other.blockedNow == blockedNow &&
      other.status == status;

  @override
  int get hashCode => Object.hash(raw, blockedNow, status);
}
