import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../state/control_store.dart';
import 'dialogs.dart';
import 'sheet.dart';
import 'theme.dart';

/// Something a lock can be put on.
///
/// Blocks were the only lockable thing at first. Uninstall protection is the
/// second, and it is the more important one: a block you can escape by deleting
/// the app is not locked at all. Both go through the same sheet so the promise
/// reads identically wherever it is made.
class LockTarget {
  const LockTarget({
    required this.name,
    required this.lock,
    required this.onLock,
    required this.onUnlock,
    required this.onEmergencyUnlock,
    this.remaining,
  });

  factory LockTarget.forBlock(ControlStore store, Block block) => LockTarget(
        name: block.name,
        lock: block.lock,
        remaining: store.lockRemaining(block),
        onLock: ({duration, password}) =>
            store.lockBlock(block.id, duration: duration, password: password),
        onUnlock: (password) => store.unlockBlock(block.id, password),
        onEmergencyUnlock: () => store.useEmergencyUnlock(block.id),
      );

  factory LockTarget.forProtection(ControlStore store) => LockTarget(
        name: 'App deletion blocked',
        lock: store.protectionLock,
        remaining: store.protectionLockRemaining,
        onLock: ({duration, password}) =>
            store.lockProtection(duration: duration, password: password),
        onUnlock: store.unlockProtection,
        onEmergencyUnlock: store.emergencyUnlockProtection,
      );

  final String name;
  final Lock lock;
  final Duration? remaining;

  final Future<void> Function({Duration? duration, String? password}) onLock;
  final Future<bool> Function(String password) onUnlock;
  final Future<bool> Function() onEmergencyUnlock;

  bool get isLocked => lock.kind != LockKind.none;
}

/// Arms or releases a lock.
///
/// The wording is blunt on purpose. A timed lock is the one irreversible thing
/// in the app, and someone choosing "1 year" at 9pm on a Sunday should have
/// read what that means before the sheet closes.
abstract final class LockSheet {
  static const durations = <(String, Duration)>[
    ('24 hours', Duration(days: 1)),
    ('1 week', Duration(days: 7)),
    ('1 month', Duration(days: 30)),
    ('3 months', Duration(days: 90)),
    ('1 year', Duration(days: 365)),
  ];

  static Future<void> show(BuildContext context, Block block) => showFor(
        context,
        LockTarget.forBlock(StoreScope.of(context), block),
      );

  static Future<void> showFor(BuildContext context, LockTarget target) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ControlColors.of(context).background,
      builder: (_) => target.isLocked
          ? _UnlockSheet(target: target)
          : _ArmSheet(target: target),
    );
  }
}

/// The same chrome as every other sheet: grabber, a header with the way out
/// on the left, then the choices.
class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: title,
      leading: SheetAction('Close', onPressed: () => Navigator.pop(context)),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.cardRaised,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 16, color: danger ? colors.heavy : null),
          ),
        ),
      ),
    );
  }
}

class _ArmSheet extends StatelessWidget {
  const _ArmSheet({required this.target});

  final LockTarget target;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);

    return _SheetShell(
      title: 'Lock',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Text(
            'Lock ${target.name}? A timed lock cannot be opened early, not even '
            'with your password. Only emergency unlocks '
            '(${store.emergencyUnlocks.remaining} left) break it.',
            style:
                TextStyle(fontSize: 16, height: 1.35, color: colors.textMuted),
          ),
        ),
        _SheetOption(
          label: 'Until I unlock it (set password)',
          onTap: () async {
            final navigator = Navigator.of(context);
            final password = await _PasswordDialog.show(
              context,
              title: 'Set a password',
              action: 'Lock',
              confirm: true,
            );
            if (password == null) return;
            await target.onLock(password: password);
            navigator.pop();
          },
        ),
        for (final option in LockSheet.durations)
          _SheetOption(
            label: option.$1,
            onTap: () async {
              final navigator = Navigator.of(context);
              final confirmed = await _confirmTimed(context, option.$1);
              if (!confirmed) return;
              await target.onLock(duration: option.$2);
              navigator.pop();
            },
          ),
      ],
    );
  }

  /// A second tap for the irreversible choice. Everything else in this app is
  /// undoable; this is not.
  Future<bool> _confirmTimed(BuildContext context, String label) =>
      confirmAction(
        context,
        icon: Icons.lock_clock_outlined,
        tone: DialogTone.caution,
        title: 'Lock for $label?',
        message: 'You will not be able to change ${target.name} for $label.',
        detail: const DialogNote(
          icon: Icons.key_off_rounded,
          text: 'There is no password that opens it early.',
          tone: DialogTone.caution,
        ),
        confirmLabel: 'Lock $label',
      );
}

class _UnlockSheet extends StatelessWidget {
  const _UnlockSheet({required this.target});

  final LockTarget target;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);
    final remaining = target.remaining;
    final isTimed = target.lock.kind == LockKind.timed && remaining != null;

    return _SheetShell(
      title: 'Locked',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Text(
            isTimed
                ? '${target.name} is locked for another '
                    '${_humanise(remaining)}. No password opens it early.'
                : '${target.name} is locked. Enter your password to open it.',
            style:
                TextStyle(fontSize: 16, height: 1.35, color: colors.textMuted),
          ),
        ),
        if (!isTimed)
          _SheetOption(
            label: 'Enter password',
            onTap: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final password = await _PasswordDialog.show(
                context,
                title: 'Unlock ${target.name}',
                action: 'Unlock',
              );
              if (password == null) return;

              if (await target.onUnlock(password)) {
                navigator.pop();
              } else {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Wrong password.')),
                );
              }
            },
          ),
        _SheetOption(
          label: store.emergencyUnlocks.isExhausted
              ? 'No emergency unlocks left'
              : 'Use an emergency unlock '
                  '(${store.emergencyUnlocks.remaining} left)',
          danger: true,
          onTap: store.emergencyUnlocks.isExhausted
              ? () {}
              : () async {
                  final navigator = Navigator.of(context);
                  final confirmed = await _confirmEmergency(context, store);
                  if (!confirmed) return;
                  await target.onEmergencyUnlock();
                  navigator.pop();
                },
        ),
      ],
    );
  }

  Future<bool> _confirmEmergency(BuildContext context, ControlStore store) =>
      confirmAction(
        context,
        icon: Icons.emergency_outlined,
        tone: DialogTone.danger,
        title: 'Spend an emergency unlock?',
        message: 'This opens ${target.name} now. Emergency unlocks never '
            'refill.',
        detail: _UnlockPips(
          total: store.emergencyUnlocks.total,
          remaining: store.emergencyUnlocks.remaining,
        ),
        cancelLabel: 'Keep it',
        confirmLabel: 'Spend it',
      );

  static String _humanise(Duration duration) {
    if (duration.inDays >= 1) {
      return '${duration.inDays} day${duration.inDays == 1 ? '' : 's'}';
    }
    if (duration.inHours >= 1) {
      return '${duration.inHours} hour${duration.inHours == 1 ? '' : 's'}';
    }
    return '${duration.inMinutes} minute${duration.inMinutes == 1 ? '' : 's'}';
  }
}

/// Asks for a block password: twice when it is being set, since a typo there
/// keeps the block shut until an emergency unlock is spent.
abstract final class _PasswordDialog {
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String action,
    bool confirm = false,
  }) => showControlDialog<String>(
    context,
    builder: (_) => SecretDialog(
      icon: confirm ? Icons.password_rounded : Icons.lock_open_rounded,
      title: title,
      message: confirm
          ? 'Asked twice: a typo here keeps it locked until an emergency '
                'unlock is spent.'
          : null,
      action: action,
      fieldLabel: 'Password',
      repeatLabel: confirm ? 'Repeat password' : null,
      validate: (secret) => secret.isEmpty ? 'Enter a password.' : null,
    ),
  );
}

/// The emergency unlocks as a row of dots: those that stay, the one about to
/// go, and those already gone.
class _UnlockPips extends StatelessWidget {
  const _UnlockPips({required this.total, required this.remaining});

  final int total;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final left = remaining - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < total; i++)
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < left
                        ? scheme.primary
                        : i == left
                        ? scheme.error.withValues(alpha: 0.18)
                        : Colors.transparent,
                    border: Border.all(
                      color: i < left
                          ? scheme.primary
                          : i == left
                          ? scheme.error
                          : scheme.outlineVariant,
                      width: 2,
                    ),
                  ),
                  child: i == left
                      ? Icon(Icons.close_rounded, size: 11, color: scheme.error)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            left == 0
                ? 'This is your last one.'
                : '$left of $total left after this',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              color: left == 0 ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
