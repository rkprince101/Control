import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../platform/platform_models.dart';
import 'adb_prerequisites.dart';
import 'sheet.dart';
import 'theme.dart';

/// Walks through provisioning Control as device owner.
///
/// This is the strongest configuration Android offers an app: safe mode,
/// `adb uninstall`, a second user, and OEM app managers all stop working. It
/// needs a computer and every account off the phone for a minute, which is
/// why it is a guided screen rather than a switch, and why the price is
/// stated first.
///
/// The sheet does not try to predict whether the command will be accepted.
/// The one API that sounds like it would, `isProvisioningAllowed`, answers for
/// the setup wizard and says no on every phone past setup, which used to send
/// people to a factory reset they did not need. What the command actually
/// checks (accounts, other users, Xiaomi's extra switch) is listed instead,
/// with the exact error each one produces.
class DeviceOwnerSheet extends StatefulWidget {
  const DeviceOwnerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ControlColors.of(context).background,
      builder: (_) => const DeviceOwnerSheet(),
    );
  }

  @override
  State<DeviceOwnerSheet> createState() => _DeviceOwnerSheetState();
}

class _DeviceOwnerSheetState extends State<DeviceOwnerSheet> {
  DeviceOwnerStatus? _status;
  String? _error;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // Not called directly from initState: reading an InheritedWidget there
    // throws, the throw lands in an unawaited future, and the sheet sits on its
    // spinner forever with nothing in the log.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      final status = await StoreScope.read(context).deviceOwnerStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _checking = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final error = _error;

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Column(
        children: [
          const SheetGrabber(),
          _header(),
          Expanded(
            child: error != null
                ? _Failure(message: error, onRetry: _check)
                : status == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    children: status.isOwner
                        ? _provisioned(status)
                        : _setup(status),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() => SheetHeader(
    title: 'Locked tier',
    leading: SheetAction('Close', onPressed: () => Navigator.pop(context)),
    trailing: SheetAction(
      'Recheck',
      primary: true,
      onPressed: _checking ? null : _check,
    ),
  );

  // Already provisioned -------------------------------------------------------

  List<Widget> _provisioned(DeviceOwnerStatus status) {
    final store = StoreScope.of(context);
    final blocked = store.protection.uninstallBlocked;

    return [
      _Banner(
        icon: Icons.verified_user_rounded,
        tone: _Tone.good,
        title: 'Control is device owner',
        body: blocked
            ? 'Uninstall is blocked at the system level. Safe mode, adb, and a '
                  'second user all fail. Only a factory reset removes Control now.'
            : 'The hard uninstall block is available but not switched on yet.',
      ),
      if (!blocked) ...[
        const SizedBox(height: 18),
        _ActionButton(
          label: 'Block uninstall permanently',
          icon: Icons.lock_rounded,
          onTap: () async {
            await store.setUninstallBlocked(true);
            await _check();
          },
        ),
      ],
      const SizedBox(height: 18),
      _Note(
        'To undo it later: turn the block off here first, then run '
        '`adb shell dpm remove-active-admin ${status.component}`. Skipping the '
        'first step leaves a device owner that only a factory reset clears.',
      ),
    ];
  }

  // Not yet provisioned -------------------------------------------------------

  Future<void> _open(SystemScreen screen) async {
    final opened = await StoreScope.read(context).openSystemScreen(screen);
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This phone has no such screen.')),
    );
  }

  List<Widget> _setup(DeviceOwnerStatus status) => [
    const _Banner(
      icon: Icons.info_outline_rounded,
      tone: _Tone.good,
      title: 'No factory reset needed',
      body:
          'Android hands device owner to an app only from a computer, and '
          'only while no accounts and no other users are on the phone. '
          'Signing out of the accounts for a minute is enough: run one '
          'command, then sign back in.',
    ),
    if (status.isXiaomi) ...[
      const SizedBox(height: 14),
      _Banner(
        icon: Icons.warning_amber_rounded,
        tone: _Tone.warn,
        title: 'Xiaomi, Redmi and POCO: one extra switch',
        body:
            'Without it the command fails with "Calling identity is not '
            'authorized". In Developer options, turn on USB debugging '
            '(Security settings) as well as USB debugging. It asks you to '
            'sign in to a Mi account and may want a SIM card, so do it '
            'before signing out of everything.',
        action: _LinkButton(
          label: 'Open Developer options',
          onTap: () => _open(SystemScreen.developer),
        ),
      ),
    ],
    const SizedBox(height: 20),
    const AdbPrerequisitesCard(),
    const SizedBox(height: 20),
    _Step(
      number: 1,
      title: 'Turn on USB debugging',
      body: status.isXiaomi
          ? 'Settings, About phone, tap OS version seven times, then '
                'Additional settings, Developer options. Turn on USB '
                'debugging and USB debugging (Security settings).'
          : 'Settings, About phone, tap Build number seven times, then '
                'Developer options, USB debugging.',
      child: _LinkButton(
        label: 'Open Developer options',
        onTap: () => _open(SystemScreen.developer),
      ),
    ),
    _Step(
      number: 2,
      title: 'Sign out of every account, for now',
      body:
          'Settings, Accounts: remove each one listed there, Google'
          '${status.isXiaomi ? ', Mi account' : ''} and app accounts '
          'included. One left behind is enough to make the command fail. '
          'Your data stays in the cloud and comes back when you sign in.',
      child: _LinkButton(
        label: 'Open Accounts',
        onTap: () => _open(SystemScreen.accounts),
      ),
    ),
    _Step(
      number: 3,
      title: 'Remove other users and spaces',
      body: status.isXiaomi
          ? 'Second space and Dual apps each count as another user. Turn '
                'them off, and remove any guest.'
          : 'Guest, other users, and spaces like Secure Folder or a work '
                'profile each count. Remove them for now.',
      child: _LinkButton(
        label: 'Open Users',
        onTap: () => _open(SystemScreen.users),
      ),
    ),
    const _Step(
      number: 4,
      title: 'Connect, and check the computer sees the phone',
      body:
          'Accept the Allow USB debugging prompt on the phone. The phone has '
          'to be listed as device: unauthorized means the prompt was not '
          'accepted, an empty list means the driver or the cable.',
      child: _Command(command: 'adb devices'),
    ),
    _Step(
      number: 5,
      title: 'Run the provisioning command',
      body:
          'Copy it rather than typing it: one wrong letter in the name '
          'fails. Nothing changes unless it succeeds.',
      child: _Command(command: status.command),
    ),
    const _Step(
      number: 6,
      title: 'Press Recheck, then sign back in',
      body:
          'Once this sheet says Control is device owner, accounts and '
          'spaces no longer matter. Add them back.',
      last: true,
    ),
    const SizedBox(height: 24),
    const _FixList(),
    const SizedBox(height: 18),
    const _Note(
      'If nothing above gets the command accepted, a factory reset with '
      'every account skipped during setup always does. It wipes the phone, '
      'so it is the last resort, not the first. Hard mode already covers '
      'every route to uninstalling that starts on the phone itself; device '
      'owner adds the routes that start on a computer or in safe mode.',
    ),
  ];
}

/// What the command prints when it refuses, and what to do about each.
class _FixList extends StatelessWidget {
  const _FixList();

  static const _fixes = [
    (
      error: 'Calling identity is not authorized',
      fix:
          'On Xiaomi, Redmi and POCO: turn on USB debugging (Security '
          'settings) in Developer options. Elsewhere, check the command was '
          'copied, not typed.',
    ),
    (
      error: 'Unknown admin / Unknown component',
      fix:
          'The name after set-device-owner is mistyped. Copy the command '
          'above.',
    ),
    (
      error: 'there are already some accounts on the device',
      fix:
          'An account is still signed in. Check Settings, Accounts again, '
          'including app accounts.',
    ),
    (
      error: 'there are already several users on the device',
      fix:
          'A second user, guest, Second space, Dual apps or work profile is '
          'still there. Remove it.',
    ),
    (
      error: 'device owner is already set',
      fix:
          'Another app, often a work or school one, already owns the phone. '
          'There can only be one.',
    ),
    (
      error: 'no devices/emulators found, or unauthorized',
      fix:
          'The computer cannot see the phone. See What you need on the '
          'computer, above.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    // A Material rather than a coloured box: the tile paints its ink on the
    // nearest Material, and a coloured box in between hid it (and tripped a
    // framework assertion in debug builds).
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.build_circle_outlined, color: colors.textMuted),
          title: const Text(
            'If the command fails',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Text(
            'Find the error it printed',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (:error, :fix) in _fixes)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      error,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fix,
                      style: TextStyle(color: colors.textMuted, height: 1.4),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A quiet button under a step that opens the screen the step talks about.
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: FilledButton.tonalIcon(
      onPressed: onTap,
      icon: const Icon(Icons.open_in_new_rounded, size: 18),
      label: Text(label),
    ),
  );
}

/// Shown instead of an endless spinner when the status call fails.
class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colors.medium, size: 28),
            const SizedBox(height: 12),
            const Text(
              'Could not read the device state',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

enum _Tone { good, warn }

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final _Tone tone;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    final accent = tone == _Tone.good ? colors.light : colors.medium;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(height: 1.4)),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    this.child,
    this.last = false,
  });

  final int number;
  final String title;
  final String body;
  final Widget? child;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.cardRaised,
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (!last)
                Expanded(child: Container(width: 2, color: colors.cardRaised)),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: TextStyle(color: colors.textMuted, height: 1.4),
                  ),
                  if (child != null) ...[const SizedBox(height: 10), child!],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Command extends StatelessWidget {
  const _Command({required this.command});

  final String command;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              command,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: command));
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Command copied.')));
            },
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.light.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.light),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: colors.light),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: colors.light,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: ControlColors.of(context).textMuted,
      fontSize: 12,
      height: 1.5,
    ),
  );
}
