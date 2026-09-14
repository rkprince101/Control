import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../platform/platform_models.dart';
import '../state/control_store.dart';
import 'control_page.dart';
import 'controls.dart';
import 'device_owner_sheet.dart';
import 'lock_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);

    return ControlPage(
      title: 'settings',
      children: [

        const SectionLabel('Security'),
        ControlCard(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            children: [
              _Row(
                icon: Icons.shield_outlined,
                iconColor: colors.medium,
                label: 'Protection',
                value: store.protection.tier.label,
              ),
              Divider(height: 1, color: colors.divider),
              _Row(
                icon: Icons.lock_reset_rounded,
                iconColor: colors.medium,
                label: 'Emergency unlocks',
                value: '${store.emergencyUnlocks.remaining} of '
                    '${store.emergencyUnlocks.total}',
              ),
              Divider(height: 1, color: colors.divider),
              _DeletionRow(store: store),
              Divider(height: 1, color: colors.divider),
              _HardModeRow(store: store),
              Divider(height: 1, color: colors.divider),
              _Row(
                icon: Icons.verified_user_outlined,
                iconColor: store.protection.uninstallBlocked
                    ? colors.light
                    : colors.textMuted,
                label: 'Uninstall-proof setup',
                value: store.protection.uninstallBlocked ? 'done' : 'guide',
                onTap: () => DeviceOwnerSheet.show(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Note(
          'Emergency unlocks free a locked block when you have forgotten the '
          'password. They never refill, so guard them.',
        ),
        const SizedBox(height: 24),

        const SectionLabel('Permissions'),
        ControlCard(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            children: [
              _PermissionRow(
                icon: Icons.accessibility_new_rounded,
                label: 'App blocking',
                granted: store.accessibilityEnabled,
                onTap: store.openAccessibilitySettings,
              ),
              Divider(height: 1, color: colors.divider),
              _PermissionRow(
                icon: Icons.hourglass_empty_rounded,
                label: 'Screen time',
                granted: store.usageAccessGranted,
                onTap: store.openUsageAccessSettings,
              ),
              Divider(height: 1, color: colors.divider),
              _PermissionRow(
                icon: Icons.directions_walk_rounded,
                label: 'Steps',
                granted: store.stepsStatus.usable,
                subtitle: store.stepsStatus.available
                    ? null
                    : 'No step counter on this device',
                onTap: store.requestStepsPermission,
              ),
              Divider(height: 1, color: colors.divider),
              _PermissionRow(
                icon: Icons.place_outlined,
                label: 'Location',
                granted: store.locationStatus.usable,
                // Granted but switched off at the system level is a common
                // state, and it needs a different fix from a missing grant.
                subtitle: store.locationStatus.granted &&
                        !store.locationStatus.enabled
                    ? 'Location services are switched off'
                    : 'Used only when you tap Check in at a place',
                onTap: store.requestLocationPermission,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Note(
          'App blocking uses an accessibility service to see which app you just '
          'opened. It reads the app name only: no screen contents, and nothing '
          'leaves your device.',
        ),
        const SizedBox(height: 24),

        const SectionLabel('Reports'),
        ControlCard(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.summarize_outlined,
                      size: 22,
                      color: store.weeklyReport
                          ? colors.light
                          : colors.textMuted,
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text('Weekly report', style: TextStyle(fontSize: 16)),
                    ),
                    Switch(
                      value: store.weeklyReport,
                      onChanged: store.setWeeklyReport,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  'A summary of your week on Sunday evening. Everything in it '
                  'is already on the device; nothing is sent anywhere.',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        const SectionLabel('Appearance'),
        ControlCard(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in AppThemeChoice.values)
                ControlChip(
                  label: choice.label,
                  selected: store.theme == choice,
                  onTap: () => store.setTheme(choice),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          text,
          style: TextStyle(
            color: ControlColors.of(context).textMuted,
            height: 1.4,
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor ?? colors.textMuted),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uninstall protection, stated at the rung it is actually on.
///
/// Device admin used to block uninstalls. It does not any more: current Android
/// offers "Deactivate & uninstall" as a single step from the app info screen,
/// so admin alone buys a confirmation dialog and nothing else. Saying otherwise
/// here would be the one lie that matters in a commitment app.
class _DeletionRow extends StatelessWidget {
  const _DeletionRow({required this.store});

  final ControlStore store;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    final protection = store.protection;

    final (value, subtitle) = switch (protection) {
      ProtectionStatus(uninstallBlocked: true) => (
          'permanent',
          'Blocked at device-owner level. Removing Control needs a factory '
              'reset.',
        ),
      ProtectionStatus(deviceOwner: true) => (
          'available',
          'This device is provisioned as device owner. Tap to make the '
              'uninstall block permanent.',
        ),
      ProtectionStatus(adminActive: true) => (
          'partial',
          'Device admin is held, which adds a confirmation step. Modern Android '
              'still allows Deactivate and uninstall in one go, so turn on Hard '
              'mode below for real friction.',
        ),
      _ => (
          'off',
          'Control can be uninstalled right now, which clears every block.',
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _Row(
                icon: Icons.delete_forever_outlined,
                iconColor:
                    protection.adminActive ? colors.medium : colors.textMuted,
                label: 'App deletion blocked',
                value: value,
                onTap: () => _act(context),
              ),
            ),
            const SizedBox(width: 10),
            _ProtectionLockButton(store: store),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            subtitle,
            style: TextStyle(color: colors.textMuted, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    );
  }

  Future<void> _act(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    if (!store.protection.adminActive) {
      await store.requestDeviceAdmin();
      return;
    }

    // Device owner can go one rung further, in place, with no reset.
    if (store.protection.deviceOwner && !store.protection.uninstallBlocked) {
      await store.setUninstallBlocked(true);
      return;
    }

    final released = await store.releaseProtection();
    if (released) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'A block is still under a timed lock. Protection stays on until it '
          'expires.',
        ),
      ),
    );
  }
}

/// Locks uninstall protection, using the same sheet the block cards use.
class _ProtectionLockButton extends StatelessWidget {
  const _ProtectionLockButton({required this.store});

  final ControlStore store;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    final locked = store.protectionLock.kind != LockKind.none;

    return InkWell(
      onTap: () =>
          LockSheet.showFor(context, LockTarget.forProtection(store)),
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: locked
              ? colors.medium.withValues(alpha: 0.22)
              : colors.cardRaised,
        ),
        child: Icon(
          locked ? Icons.lock : Icons.lock_open,
          size: 17,
          color: locked ? colors.medium : colors.textMuted,
        ),
      ),
    );
  }
}

/// The tamper guard, offered plainly as the deterrent it is.
class _HardModeRow extends StatelessWidget {
  const _HardModeRow({required this.store});

  final ControlStore store;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.gpp_maybe_outlined,
                size: 22,
                color: store.hardMode ? colors.light : colors.textMuted,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text('Hard mode', style: TextStyle(fontSize: 16)),
              ),
              Switch(
                value: store.hardMode,
                // Locked protection cannot be switched off from in here; that
                // is the entire point of the lock beside it.
                onChanged: store.protectionLocked && store.hardMode
                    ? null
                    : (value) => _toggle(context, value),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            store.protectionLocked
                ? 'Locked. Hard mode cannot be switched off until the lock '
                    'beside App deletion blocked opens.'
                : store.hardMode
                    ? 'Control closes the Android screens used to uninstall or '
                        'disable it. Rebooting into safe mode, or turning off '
                        'App blocking first, still gets past it.'
                    : 'Closes the Android screens used to uninstall or disable '
                        'Control. Needs App blocking to be on.',
            style: TextStyle(color: colors.textMuted, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    );
  }

  Future<void> _toggle(BuildContext context, bool value) async {
    final messenger = ScaffoldMessenger.of(context);

    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: ControlColors.of(context).card,
          title: const Text('Turn on Hard mode?'),
          content: const Text(
            'Control will close Android settings screens that lead to '
            'uninstalling or disabling it, including its own accessibility '
            'setting. Turn it off here first when you genuinely want to remove '
            'the app.',
            style: TextStyle(height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Turn on'),
            ),
          ],
        ),
      );
      if (!(confirmed ?? false)) return;
    }

    final applied = await store.setHardMode(value);
    if (applied) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'A block is still under a timed lock. Hard mode stays on until it '
          'expires.',
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.label,
    required this.granted,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final bool granted;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: colors.textMuted, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 16)),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                ],
              ),
            ),
            Icon(
              granted ? Icons.check_circle : Icons.error_outline,
              color: granted ? colors.light : colors.medium,
            ),
          ],
        ),
      ),
    );
  }
}
