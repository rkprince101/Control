import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../state/control_store.dart';
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
  Future<bool> _confirmTimed(BuildContext context, String label) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ControlColors.of(context).card,
        title: Text('Lock for $label?'),
        content: Text(
          'You will not be able to change ${target.name} for $label. There is '
          'no password that opens it early.',
          style: const TextStyle(height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Lock $label'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
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

  Future<bool> _confirmEmergency(
    BuildContext context,
    ControlStore store,
  ) async {
    final left = store.emergencyUnlocks.remaining - 1;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ControlColors.of(context).card,
        title: const Text('Spend an emergency unlock?'),
        content: Text(
          'This opens ${target.name} now and leaves you $left. They never '
          'refill.',
          style: const TextStyle(height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Spend it'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

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

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({
    required this.title,
    required this.action,
    required this.confirm,
  });

  final String title;
  final String action;

  /// Asks twice when setting a new password: a typo here locks the target until
  /// an emergency unlock is spent.
  final bool confirm;

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String action,
    bool confirm = false,
  }) =>
      showDialog<String>(
        context: context,
        builder: (_) =>
            _PasswordDialog(title: title, action: action, confirm: confirm),
      );

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _first.text;
    if (password.isEmpty) {
      setState(() => _error = 'Enter a password.');
      return;
    }
    if (widget.confirm && password != _second.text) {
      setState(() => _error = 'The two entries do not match.');
      return;
    }
    Navigator.pop(context, password);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ControlColors.of(context).card,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _first,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => widget.confirm ? null : _submit(),
          ),
          if (widget.confirm)
            TextField(
              controller: _second,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repeat password'),
              onSubmitted: (_) => _submit(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: ControlColors.of(context).heavy),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}
