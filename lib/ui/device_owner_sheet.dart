import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../platform/platform_models.dart';
import 'adb_prerequisites.dart';
import 'sheet.dart';
import 'theme.dart';

/// Walks through provisioning Control as device owner.
///
/// This is the only configuration on Android where an uninstall is genuinely
/// impossible: safe mode, `adb uninstall`, a second user, and every OEM app
/// manager all stop working. It costs a factory reset, which is why it is a
/// guided screen rather than a switch, and why the price is stated first.
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
      final status = await StoreScope.of(context).deviceOwnerStatus();
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
                        : status.provisioningAllowed
                            ? _ready(status)
                            : _blocked(status),
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

  // Ready to provision --------------------------------------------------------

  List<Widget> _ready(DeviceOwnerStatus status) => [
        const _Banner(
          icon: Icons.check_circle_outline,
          tone: _Tone.good,
          title: 'This device is ready',
          body: 'No accounts are signed in, so the provisioning command will '
              'be accepted. Run it before adding your Google account back.',
        ),
        const SizedBox(height: 20),
        const AdbPrerequisitesCard(),
        const SizedBox(height: 20),
        const _Step(
          number: 1,
          title: 'Enable USB debugging on the phone',
          body: 'Settings, About phone, tap Build number seven times, then '
              'Developer options, USB debugging.',
        ),
        const _Step(
          number: 2,
          title: 'Connect the phone to the computer',
          body: 'Accept the Allow USB debugging prompt on the phone. If no '
              'prompt appears, the driver is the usual reason.',
        ),
        _Step(
          number: 3,
          title: 'Check the computer can see it',
          body: 'Your phone has to be listed as device. The word unauthorized '
              'means the prompt was not accepted; an empty list means the '
              'driver or the cable.',
          child: const _Command(command: 'adb devices'),
        ),
        _Step(
          number: 4,
          title: 'Run the provisioning command',
          body: 'Anything that fails here fails safely: nothing changes until '
              'it succeeds.',
          child: _Command(command: status.command),
        ),
        const _Step(
          number: 5,
          title: 'Come back and press Recheck',
          body: 'Then sign back into your accounts. Provisioning is done and '
              'accounts no longer matter.',
          last: true,
        ),
      ];

  // Cannot provision ----------------------------------------------------------

  List<Widget> _blocked(DeviceOwnerStatus status) => [
        const _Banner(
          icon: Icons.info_outline_rounded,
          tone: _Tone.warn,
          title: 'A factory reset is needed first',
          body: 'Android refuses to hand out device owner once any account is '
              'signed in. That is a system rule, not something Control can '
              'work around.',
        ),
        const SizedBox(height: 20),
        const _Step(
          number: 1,
          title: 'Back up anything you care about',
          body: 'This wipes the phone. Photos, chats, two-factor apps: all of '
              'it.',
        ),
        const _Step(
          number: 2,
          title: 'Factory reset the phone',
          body: 'Settings, System, Reset options, Erase all data.',
        ),
        const _Step(
          number: 3,
          title: 'Skip every account during setup',
          body: 'Do not sign into Google yet. One account is enough to make '
              'the command fail.',
        ),
        const _Step(
          number: 4,
          title: 'Set the computer up first',
          body: 'See what you need on the computer, below. Worth doing before '
              'the reset, so the phone is not sitting wiped while you download '
              'tools.',
        ),
        _Step(
          number: 5,
          title: 'Install Control and run the command',
          body: 'With USB debugging on, from the computer:',
          child: _Command(command: status.command),
        ),
        const _Step(
          number: 6,
          title: 'Sign back in',
          body: 'Once provisioning is done, accounts no longer matter.',
          last: true,
        ),
        const SizedBox(height: 20),
        const AdbPrerequisitesCard(),
        const SizedBox(height: 18),
        _Note(
          'Worth being honest about the trade: this is a real cost for a real '
          'guarantee. Hard mode covers every route to uninstalling that starts '
          'on the phone itself, and needs none of this. The reset only buys '
          'the routes that start on a computer or in safe mode.',
        ),
      ];
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
  });

  final IconData icon;
  final _Tone tone;
  final String title;
  final String body;

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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Command copied.')),
              );
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
