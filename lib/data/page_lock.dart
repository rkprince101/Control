import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A PIN that hides chosen pages until it is entered.
///
/// The PIN itself is never stored: only a random salt and the SHA-256 of salt
/// and PIN. This is privacy from someone picking up the phone, not a vault;
/// four digits fall to any patient guesser with the file in hand, so a slow
/// hash would add delay to every keypress and no real protection.
class PageLock {
  const PageLock({this.hash = '', this.salt = '', this.pages = const {}});

  static const minLength = 4;
  static const maxLength = 12;

  final String hash;
  final String salt;

  /// Destination names the PIN guards.
  final Set<String> pages;

  bool get enabled => hash.isNotEmpty;

  /// The same pages behind a new PIN, with a fresh salt.
  PageLock withPin(String pin) {
    final salt = _newSalt();
    return PageLock(hash: _hash(pin, salt), salt: salt, pages: pages);
  }

  PageLock withPage(String page, {required bool locked}) => PageLock(
    hash: hash,
    salt: salt,
    pages: locked ? {...pages, page} : ({...pages}..remove(page)),
  );

  bool verify(String pin) => enabled && _hash(pin, salt) == hash;

  static String _newSalt() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt$pin')).toString();

  Map<String, Object?> toJson() => {
    'hash': hash,
    'salt': salt,
    'pages': pages.toList(),
  };

  static PageLock fromJson(Object? raw) {
    if (raw is! Map) return const PageLock();
    final hash = raw['hash'];
    final salt = raw['salt'];
    if (hash is! String || salt is! String || hash.isEmpty) {
      return const PageLock();
    }
    final pages = raw['pages'];
    return PageLock(
      hash: hash,
      salt: salt,
      pages: pages is List ? pages.whereType<String>().toSet() : const {},
    );
  }
}
