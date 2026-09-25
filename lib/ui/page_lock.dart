import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/page_lock.dart';
import '../main.dart';
import 'dialogs.dart';
import 'navigation.dart';
import 'theme.dart';
import 'widgets.dart';

/// Stands in for a page that is behind the PIN until the PIN is entered.
///
/// The page is not built at all while locked, so nothing of it can be read
/// from the widget tree. The search bar stays, so the drawer is still one tap
/// away. The PIN is checked as it is typed: the page opens on the digit that
/// completes it, with no Unlock button to find.
class PageLockGate extends StatefulWidget {
  const PageLockGate({
    required this.destination,
    required this.active,
    required this.child,
    super.key,
  });

  final Destination destination;

  /// Whether this page is the one on screen. Only that one takes the keyboard.
  final bool active;
  final Widget child;

  @override
  State<PageLockGate> createState() => _PageLockGateState();
}

class _PageLockGateState extends State<PageLockGate> {
  final _focus = FocusNode(debugLabel: 'PIN keypad');
  String _entry = '';

  @override
  void didUpdateWidget(PageLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focus.context != null) _focus.requestFocus();
      });
    } else if (!widget.active && oldWidget.active) {
      _focus.unfocus();
      _entry = '';
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _type(String digit) {
    if (_entry.length >= PageLock.maxLength) return;
    final entry = _entry + digit;
    final store = StoreScope.read(context);
    if (entry.length >= PageLock.minLength &&
        store.unlockPage(widget.destination.name, entry)) {
      _entry = '';
      return;
    }
    setState(() => _entry = entry);
  }

  void _erase() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  void _clear() => setState(() => _entry = '');

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final character = event.character;
    if (character != null && RegExp(r'^[0-9]$').hasMatch(character)) {
      _type(character);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _erase();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _clear();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (!store.isPageLocked(widget.destination.name)) return widget.child;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ControlColors.of(context);
    // Only a whole PIN's worth of digits can be wrong.
    final wrong = _entry.length >= PageLock.minLength;
    final inShell = HomeNavigation.maybeOf(context) != null;

    final body = Focus(
      focusNode: _focus,
      autofocus: widget.active,
      onKeyEvent: _onKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lock_rounded,
              size: 28,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              '${widget.destination.label} is locked',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter your PIN to open it',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 24),
          Semantics(
            label: '${_entry.length} digits entered',
            liveRegion: true,
            child: ExcludeSemantics(
              child: _PinDots(
                count: math.max(PageLock.minLength, _entry.length),
                filled: _entry.length,
                color: wrong ? colors.heavy : scheme.primary,
                track: scheme.outlineVariant,
              ),
            ),
          ),
          SizedBox(
            height: 32,
            child: Center(
              child: wrong
                  ? Text(
                      'Wrong PIN',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.heavy,
                      ),
                    )
                  : null,
            ),
          ),
          _Keypad(onDigit: _type, onErase: _erase, onClear: _clear),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.max(20.0, (constraints.maxWidth - 1120) / 2);
        return Column(
          children: [
            if (inShell) ShellSearchBar(horizontalPadding: side),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: body,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.count,
    required this.filled,
    required this.color,
    required this.track,
  });

  final int count;
  final int filled;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 10,
    alignment: WrapAlignment.center,
    children: [
      for (var i = 0; i < count; i++)
        AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 120),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < filled ? color : Colors.transparent,
            border: Border.all(color: i < filled ? color : track, width: 2),
          ),
        ),
    ],
  );
}

/// A phone-style number pad: three columns, zero under the eight, and erase
/// beside it. Long-press erase to start again.
class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onErase,
    required this.onClear,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onErase;
  final VoidCallback onClear;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String digit) => _Key(
      label: digit,
      onTap: () => onDigit(digit),
      child: Text(digit, style: Theme.of(context).textTheme.headlineSmall),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final digit in row) key(digit)],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: _Key.extent + 2 * _Key.gap),
            key('0'),
            _Key(
              label: 'Erase',
              onTap: onErase,
              onLongPress: onClear,
              tonal: false,
              child: Icon(
                Icons.backspace_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.tonal = true,
  });

  static const extent = 72.0;
  static const gap = 8.0;

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  final bool tonal;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(gap),
    child: Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: tonal
              ? Theme.of(context).colorScheme.surfaceContainerHigh
              : Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: SizedBox.square(
              dimension: extent,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Asks for a PIN. With [confirm] it asks twice and returns only a match.
/// Null when cancelled.
abstract final class PinDialog {
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String action,
    bool confirm = false,
  }) => showControlDialog<String>(
    context,
    builder: (_) => SecretDialog(
      icon: confirm ? Icons.pin_outlined : Icons.lock_open_rounded,
      title: title,
      message: confirm
          ? '${PageLock.minLength} to ${PageLock.maxLength} digits. Locked '
                'pages ask for it each time you come back.'
          : 'The PIN that locks your pages.',
      action: action,
      fieldLabel: 'PIN',
      repeatLabel: confirm ? 'Repeat PIN' : null,
      digitsOnly: true,
      maxLength: PageLock.maxLength,
      validate: (pin) => pin.length < PageLock.minLength
          ? 'Use at least ${PageLock.minLength} digits.'
          : null,
    ),
  );
}

/// The pages a PIN can guard: everything but Settings, which holds the PIN's
/// own controls and so must always be reachable.
const lockableDestinations = [
  Destination.blocks,
  Destination.habits,
  Destination.todos,
  Destination.notes,
  Destination.money,
  Destination.insights,
];

/// Settings for the PIN: set it, then choose what it guards. Once a PIN
/// exists, changing any of this asks for it first.
class AppLockCard extends StatelessWidget {
  const AppLockCard({super.key});

  Future<void> _setPin(BuildContext context, {required bool change}) async {
    final store = StoreScope.read(context);
    final pin = await PinDialog.show(
      context,
      title: change ? 'New PIN' : 'Set a PIN',
      action: 'Save',
      confirm: true,
    );
    if (pin != null) await store.setPin(pin);
  }

  Future<void> _unlock(BuildContext context) async {
    final store = StoreScope.read(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final pin = await PinDialog.show(
      context,
      title: 'Enter PIN',
      action: 'Unlock',
    );
    if (pin == null || store.unlockLockSettings(pin)) return;
    messenger?.showSnackBar(const SnackBar(content: Text('Wrong PIN')));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);
    final lock = store.pageLock;

    if (!lock.enabled) {
      return ControlCard(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: _LockRow(
          icon: Icons.lock_outline_rounded,
          label: 'Lock pages with a PIN',
          detail: 'Hide pages behind a PIN of 4 to 12 digits',
          action: FilledButton.tonal(
            onPressed: () => _setPin(context, change: false),
            child: const Text('Set PIN'),
          ),
        ),
      );
    }

    if (!store.lockSettingsOpen) {
      return ControlCard(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: _LockRow(
          icon: Icons.lock_rounded,
          iconColor: colors.light,
          label: 'App lock is on',
          detail: 'Enter your PIN to change these settings',
          action: FilledButton.tonal(
            onPressed: () => _unlock(context),
            child: const Text('Unlock'),
          ),
        ),
      );
    }

    return ControlCard(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LockRow(
            icon: Icons.lock_open_rounded,
            iconColor: colors.light,
            label: 'PIN is set',
            detail: 'The pages you pick ask for it',
          ),
          Padding(
            // Under the label, clear of the icon.
            padding: const EdgeInsets.fromLTRB(36, 0, 0, 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _setPin(context, change: true),
                  child: const Text('Change PIN'),
                ),
                OutlinedButton(
                  onPressed: store.clearPin,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.heavy,
                  ),
                  child: const Text('Remove PIN'),
                ),
              ],
            ),
          ),
          for (final destination in lockableDestinations) ...[
            Divider(height: 1, color: colors.divider),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(destination.icon, size: 22, color: colors.textMuted),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      destination.label,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  Switch(
                    value: lock.pages.contains(destination.name),
                    onChanged: (locked) =>
                        store.setPageLocked(destination.name, locked: locked),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LockRow extends StatelessWidget {
  const _LockRow({
    required this.icon,
    required this.label,
    required this.detail,
    this.iconColor,
    this.action,
  });

  final IconData icon;
  final String label;
  final String detail;
  final Color? iconColor;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(icon, size: 22, color: iconColor ?? colors.textMuted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(color: colors.textMuted, fontSize: 14),
                ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ],
      ),
    );
  }
}
