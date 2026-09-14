/// Platform-independent rules for Control.
///
/// Contains no Flutter, no `dart:io`, and no platform channels on purpose: the
/// same decisions must run identically on Android, Windows, and iOS, and must
/// be testable without a device.
library;

export 'src/clock.dart';
export 'src/engine.dart';
export 'src/lock_policy.dart';
export 'src/models.dart';
