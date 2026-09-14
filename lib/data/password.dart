import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Salted, iterated hashing for block passwords.
///
/// The threat model is unusual and worth being clear about: the attacker is the
/// person who set the password, and they already know it. Hashing is here so
/// that a moment of weakness cannot be resolved by reading the password out of
/// storage with a file explorer, not to defend a secret from a stranger. That
/// is why iterated SHA-256 is enough and a memory-hard KDF would be theatre.
abstract final class Password {
  static const _iterations = 60000;
  static const _prefix = 'sha256';

  static String hash(String password) {
    final salt = _randomSalt();
    return _encode(salt, _derive(password, salt));
  }

  static bool verify(String password, String? encoded) {
    if (encoded == null) return false;

    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0] != _prefix) return false;

    final iterations = int.tryParse(parts[1]);
    final salt = base64Decode(parts[2]);
    if (iterations == null) return false;

    final expected = base64Decode(parts[3]);
    final actual = _derive(password, salt, iterations: iterations);
    return _constantTimeEquals(expected, actual);
  }

  static List<int> _derive(
    String password,
    List<int> salt, {
    int iterations = _iterations,
  }) {
    var digest = sha256.convert([...salt, ...utf8.encode(password)]).bytes;
    for (var i = 1; i < iterations; i++) {
      digest = sha256.convert([...salt, ...digest]).bytes;
    }
    return digest;
  }

  static String _encode(List<int> salt, List<int> digest) =>
      '$_prefix\$$_iterations\$${base64Encode(salt)}\$${base64Encode(digest)}';

  static List<int> _randomSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256));
  }

  /// Compares without an early exit. Overkill for this threat model, but the
  /// habit is cheap and the alternative is a comment explaining why not.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
