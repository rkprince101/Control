import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';

import '../data/legal.dart';
import '../main.dart';
import '../platform/platform_models.dart';
import '../state/control_store.dart';
import 'control_page.dart';
import 'disclosures.dart';
import 'about_page.dart';
import 'controls.dart';
import 'device_owner_sheet.dart';
import 'dialogs.dart';
import 'expressive_progress.dart';
import 'legal_page.dart';
import 'lock_sheet.dart';
import 'page_lock.dart';
import 'support.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);

    return ControlPage(
      title: 'Your setup',
      subtitle: 'Make Control feel right for you.',
      children: [
        HeroCard(
          tone: Theme.of(context).colorScheme.tertiaryContainer,
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: Theme.of(context).colorScheme.onTertiaryContainer,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined),
                const SizedBox(height: 12),
                const Text('Your protection'),
                const SizedBox(height: 4),
                Text(
                  store.protection.tier.label,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  store.protection.uninstallBlocked
                      ? 'Android device-owner policy blocks ordinary uninstall. '
                            'A factory reset can still remove Control.'
                      : store.hardMode && store.accessibilityEnabled
                      ? 'Hard mode adds friction, not a guarantee. '
                            'Safe mode can still bypass it.'
                      : 'A commitment, not a guarantee. '
                            'Control can still be disabled or uninstalled.',
                ),
                if (!store.accessibilityEnabled) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'App blocking is off. Blocks are not being enforced.',
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const SectionLabel('Commitment & recovery'),
        ControlCard(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            children: [
              _Row(
                icon: Icons.lock_reset_rounded,
                iconColor: colors.medium,
                label: 'Emergency unlocks',
                value:
                    '${store.emergencyUnlocks.remaining} of '
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
                label: 'Device owner setup',
                value: store.protection.uninstallBlocked
                    ? 'Policy active'
                    : 'Setup guide',
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

        const SectionLabel('Access & permissions'),
        ControlCard(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            children: [
              _PermissionRow(
                icon: Icons.accessibility_new_rounded,
                label: 'App blocking',
                subtitle: 'Enforces your app and website rules',
                granted: store.accessibilityEnabled,
                onTap: () => Disclosures.appBlocking(context),
              ),
              Divider(height: 1, color: colors.divider),
              _PermissionRow(
                icon: Icons.hourglass_empty_rounded,
                label: 'Screen time',
                subtitle: 'Reads usage totals for insights and app-time rules',
                granted: store.usageAccessGranted,
                onTap: () => Disclosures.usageAccess(context),
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
                subtitle:
                    store.locationStatus.granted &&
                        !store.locationStatus.enabled
                    ? 'Location services are switched off'
                    : 'Used only when you tap Check in at a place',
                onTap: store.requestLocationPermission,
              ),
              Divider(height: 1, color: colors.divider),
              _PermissionRow(
                icon: Icons.notifications_none_rounded,
                label: 'Notifications',
                subtitle: store.notifications.enabled
                    ? 'Habit reminders, the weekly report and the focus timer'
                    : 'Off, so reminders, the weekly report and the focus '
                          'timer cannot reach you',
                granted: store.notifications.enabled,
                onTap: store.fixNotifications,
              ),
              if (store.notifications.exactRelevant) ...[
                Divider(height: 1, color: colors.divider),
                _PermissionRow(
                  icon: Icons.alarm_rounded,
                  label: 'Exact timing',
                  subtitle: store.notifications.exactAlarms
                      ? 'Reminders and the timer\'s end arrive on the minute'
                      : 'Without it, reminders and the timer\'s end can '
                            'arrive up to a few minutes late',
                  granted: store.notifications.exactAlarms,
                  optional: true,
                  onTap: store.openExactAlarmSettings,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Note(
          'App blocking uses an accessibility service to identify the foreground '
          'app and read browser URLs for website rules. Hard mode also reads '
          'content on Android settings screens to detect attempts to disable or '
          'uninstall Control. This processing happens locally on your device.',
        ),
        const SizedBox(height: 24),

        const SectionLabel('App lock'),
        const AppLockCard(),
        const SizedBox(height: 10),
        const _Note(
          'Locked pages ask for the PIN each time you come back to Control. '
          'Settings is never locked, so the PIN can always be changed here.',
        ),
        const SizedBox(height: 24),

        const SectionLabel('Your weekly rhythm'),
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
                      child: Text(
                        'Weekly report',
                        style: TextStyle(fontSize: 16),
                      ),
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
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
              if (store.weeklyReport && !store.notifications.enabled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _NotificationsOff(
                    text:
                        'Notifications are off for Control, so the report '
                        'cannot arrive.',
                    onFix: store.fixNotifications,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        const SectionLabel('Appearance'),
        ControlCard(
          child: LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final choice in AppThemeChoice.values)
                  SizedBox(
                    width:
                        constraints.maxWidth < 240 ||
                            MediaQuery.textScalerOf(context).scale(16) > 24
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 12) / 2,
                    child: _AppearanceChoice(
                      choice: choice,
                      selected: store.theme == choice,
                      onTap: () => store.setTheme(choice),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        const SectionLabel('Motion'),
        _MotionCard(store: store),
        const SizedBox(height: 24),

        const SectionLabel('About'),
        ControlCard(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            children: [
              _Row(
                icon: Icons.info_outline_rounded,
                label: 'About Control',
                value: 'Version, the developer, GitHub',
                onTap: () => AboutPage.open(context),
              ),
              Divider(height: 1, color: colors.divider),
              _Row(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy policy',
                value: 'Everything stays on your phone',
                onTap: () => LegalPage.open(context, privacyPolicy),
              ),
              Divider(height: 1, color: colors.divider),
              _Row(
                icon: Icons.handshake_outlined,
                label: 'Terms of use',
                value: 'Free, open source, given as it is',
                onTap: () => LegalPage.open(context, termsOfUse),
              ),
              Divider(height: 1, color: colors.divider),
              _Row(
                icon: Icons.favorite_outline_rounded,
                iconColor: Theme.of(context).colorScheme.error,
                label: 'Support me',
                value: 'UPI or Buy me a coffee',
                onTap: () => SupportSheet.show(context),
              ),
              Divider(height: 1, color: colors.divider),
              _Row(
                icon: Icons.apps_rounded,
                leading: const HushroomIcon(),
                label: 'Hushroom',
                value: 'My other app, on Google Play',
                onTap: () => openHushroom(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const _Note(
          'Control is open source under the MIT licence: '
          'github.com/rkprince101/Control',
        ),
      ],
    );
  }
}

/// The wave on progress bars: whether it moves, and how fast, with a live
/// sample so the choice is made by looking rather than by reading.
class _MotionCard extends StatelessWidget {
  const _MotionCard({required this.store});

  final ControlStore store;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    final theme = Theme.of(context);
    final systemStill = MediaQuery.disableAnimationsOf(context);

    return ControlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.waves_rounded,
                size: 22,
                color: store.waveMotion == WaveMotion.off || systemStill
                    ? colors.textMuted
                    : colors.light,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text('Progress wave', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ExpressiveProgress(
            value: 0.62,
            motion: store.waveMotion,
            trackColor: colors.cardRaised,
            semanticsLabel: 'Progress wave preview',
          ),
          const SizedBox(height: 16),
          // Scrolls rather than wraps, so the three stay on one line at any
          // text size.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ControlSegmented<WaveMotion>(
              value: store.waveMotion,
              options: [
                for (final motion in WaveMotion.values) (motion, motion.label),
              ],
              onChanged: store.setWaveMotion,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            systemStill
                ? 'Animations are switched off for this device in Android '
                      'settings, so the wave stays still whatever you pick here.'
                : switch (store.waveMotion) {
                    WaveMotion.off =>
                      'The wave holds still, progress bars change length '
                          'without easing, and the stopwatch dial steps once a '
                          'second.',
                    WaveMotion.calm =>
                      'The wave drifts slowly along anything in progress, '
                          'bars and timer rings alike.',
                    WaveMotion.lively =>
                      'The wave moves at the Material pace. Livelier, and a '
                          'little more battery.',
                  },
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppearanceChoice extends StatelessWidget {
  const _AppearanceChoice({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final AppThemeChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark =
        choice == AppThemeChoice.black ||
        choice == AppThemeChoice.pitchBlack ||
        (choice == AppThemeChoice.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final background = choice == AppThemeChoice.pitchBlack
        ? Colors.black
        : dark
        ? const Color(0xFF17211D)
        : const Color(0xFFF8F5EE);
    final accent = dark ? const Color(0xFFA7D5BA) : const Color(0xFF245B43);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.secondaryContainer : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Container(
                    height: 64,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          choice == AppThemeChoice.system
                              ? Icons.brightness_auto_rounded
                              : dark
                              ? Icons.dark_mode_rounded
                              : Icons.light_mode_rounded,
                          color: accent,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 6),
                              FractionallySizedBox(
                                widthFactor: 0.65,
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8BCA7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        choice.label,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 20,
                      color: scheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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
      style: TextStyle(color: ControlColors.of(context).textMuted, height: 1.4),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.leading,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  /// Drawn in place of [icon], such as another app's own icon.
  final Widget? leading;
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
            leading ??
                Icon(icon, size: 22, color: iconColor ?? colors.textMuted),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
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
        'Policy active',
        'Android device-owner policy blocks ordinary uninstall. '
            'A factory reset can still remove Control.',
      ),
      ProtectionStatus(deviceOwner: true) => (
        'available',
        'This device is provisioned as device owner. Tap to make the '
            'Android uninstall restriction active.',
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
                iconColor: protection.adminActive
                    ? colors.medium
                    : colors.textMuted,
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
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 14,
              height: 1.4,
            ),
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

    return IconButton.filledTonal(
      tooltip: locked ? 'Manage protection lock' : 'Lock protection',
      onPressed: () =>
          LockSheet.showFor(context, LockTarget.forProtection(store)),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: Icon(
        locked ? Icons.lock : Icons.lock_open,
        size: 20,
        color: locked ? colors.medium : colors.textMuted,
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
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _toggle(BuildContext context, bool value) async {
    final messenger = ScaffoldMessenger.of(context);

    if (value) {
      final confirmed = await confirmAction(
        context,
        icon: Icons.gpp_maybe_outlined,
        tone: DialogTone.caution,
        title: 'Turn on Hard mode?',
        message:
            'Control will close the Android settings screens that lead to '
            'uninstalling or disabling it, including its own accessibility '
            'setting.',
        detail: const DialogNote(
          icon: Icons.info_outline_rounded,
          text:
              'When you genuinely want to remove the app, turn it off here '
              'first.',
          tone: DialogTone.caution,
        ),
        confirmLabel: 'Turn on',
      );
      if (!confirmed) return;
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

/// A feature that is on but cannot reach the user, with the way to fix it.
class _NotificationsOff extends StatelessWidget {
  const _NotificationsOff({required this.text, required this.onFix});

  final String text;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return Row(
      children: [
        Icon(Icons.notifications_off_outlined, size: 20, color: colors.medium),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TextStyle(color: colors.medium, height: 1.35)),
        ),
        TextButton(onPressed: onFix, child: const Text('Turn on')),
      ],
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
    this.optional = false,
  });

  final IconData icon;
  final String label;
  final bool granted;
  final String? subtitle;
  final VoidCallback onTap;

  /// Nice to have rather than needed: not granted reads as a choice, not as
  /// something broken.
  final bool optional;

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
                  const SizedBox(height: 4),
                  Text(
                    granted
                        ? 'Ready'
                        : optional
                        ? 'Optional'
                        : 'Needs attention',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: granted
                          ? colors.light
                          : optional
                          ? colors.textMuted
                          : colors.medium,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(color: colors.textMuted, fontSize: 14),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              granted
                  ? Icons.check_circle
                  : optional
                  ? Icons.chevron_right_rounded
                  : Icons.error_outline,
              color: granted
                  ? colors.light
                  : optional
                  ? colors.textMuted
                  : colors.medium,
            ),
          ],
        ),
      ),
    );
  }
}
