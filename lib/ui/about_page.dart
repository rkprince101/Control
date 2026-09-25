import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/legal.dart';
import 'control_page.dart';
import 'legal_page.dart';
import 'support.dart';
import 'theme.dart';
import 'widgets.dart';

/// What Control is, which version this is, who made it, and the way to the
/// developer's GitHub.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const AboutPage());

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(route());

  /// The launcher icon's shield, from the same paths as
  /// `ic_launcher_foreground.xml`.
  static const _shield =
      '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
      '<path fill="#32D74B" d="M18.3301,5.67L6.59008,17.41C6.15008,17.85 '
      '5.41008,17.79 5.05008,17.27C3.81008,15.46 3.08008,13.32 3.08008,11.12'
      'V6.73C3.08008,5.91 3.70008,4.98 4.46008,4.67L10.0301,2.39C11.2901,1.87 '
      '12.6901,1.87 13.9501,2.39L18.0001,4.04C18.6601,4.31 18.8301,5.17 '
      '18.3301,5.67Z"/>'
      '<path fill="#32D74B" d="M19.27,7.03963C19.92,6.48963 20.91,6.95963 '
      '20.91,7.80963V11.1196C20.91,16.0096 17.36,20.5896 12.51,21.9296C12.18,'
      '22.0196 11.82,22.0196 11.48,21.9296C10.06,21.5296 8.74001,20.8596 '
      '7.61001,19.9796C7.13001,19.6096 7.08001,18.9096 7.50001,18.4796C9.68001,'
      '16.2496 16.06,9.74963 19.27,7.03963Z"/>'
      '</svg>';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ControlColors.of(context);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final side = math.max(20.0, (constraints.maxWidth - 720) / 2);
          return CustomScrollView(
            slivers: [
              SliverAppBar.large(
                title: const Text('About'),
                backgroundColor: scheme.surface,
                surfaceTintColor: Colors.transparent,
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(side, 0, side, 40),
                sliver: SliverList.list(
                  children: [
                    // The app, as it appears on the home screen.
                    Center(
                      child: Container(
                        width: 96,
                        height: 96,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B0B0D),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: SvgPicture.string(
                          _shield,
                          semanticsLabel: 'Control',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Control',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    const _Version(),
                    const SizedBox(height: 12),
                    Text(
                      'Take your time back from your phone.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Control blocks the apps and websites that pull you in '
                      'until you have done what you promised yourself, and '
                      'keeps your habits, todos, notes and money in one calm '
                      'place. Free, open source, and everything stays on '
                      'your phone.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textMuted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _Developer(),
                    const SizedBox(height: 24),
                    const SectionLabel('More'),
                    // Material rather than a plain card, so each row's
                    // ripple shows on it.
                    Material(
                      color: colors.card,
                      borderRadius: Shapes.card,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          _LinkRow(
                            icon: Icons.code_rounded,
                            label: 'Source code',
                            detail: 'github.com/rkprince101/Control',
                            external: true,
                            onTap: () => _open(context, Links.repository),
                          ),
                          _LinkRow(
                            icon: Icons.privacy_tip_outlined,
                            label: 'Privacy policy',
                            onTap: () => LegalPage.open(context, privacyPolicy),
                          ),
                          _LinkRow(
                            icon: Icons.handshake_outlined,
                            label: 'Terms of use',
                            onTap: () => LegalPage.open(context, termsOfUse),
                          ),
                          _LinkRow(
                            icon: Icons.favorite_outline_rounded,
                            iconColor: scheme.error,
                            label: 'Support me',
                            detail: 'UPI or Buy me a coffee',
                            onTap: () => SupportSheet.show(context),
                          ),
                          _LinkRow(
                            icon: Icons.apps_rounded,
                            leading: const HushroomIcon(),
                            label: 'Hushroom',
                            detail: 'My other app, on Google Play',
                            external: true,
                            onTap: () => openHushroom(context),
                          ),
                          _LinkRow(
                            icon: Icons.receipt_long_outlined,
                            label: 'Open-source licences',
                            detail: 'The libraries Control is built on',
                            onTap: () => showLicensePage(
                              context: context,
                              applicationName: 'Control',
                              applicationLegalese:
                                  'MIT licence. Copyright (c) 2026 Rishikesh '
                                  'Prince Prajapati.',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Made with Flutter, for anyone who looked up from their '
                      'phone and wondered where the hour went.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (await openExternal(Uri.parse(url))) return;
    messenger?.showSnackBar(
      const SnackBar(content: Text('Could not open the browser.')),
    );
  }
}

/// "Version 1.0.0 (1)", read from the build; nothing until it is known.
class _Version extends StatelessWidget {
  const _Version();

  static Future<String?> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return 'Version ${info.version} (${info.buildNumber})';
    } catch (_) {
      return null;
    }
  }

  /// Read once: the build does not change while the app runs.
  static final _version = _load();

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _version,
    builder: (context, snapshot) => Text(
      snapshot.data ?? '',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: ControlColors.of(context).textMuted,
      ),
    ),
  );
}

/// Who made Control, and the way to their GitHub profile.
class _Developer extends StatelessWidget {
  const _Developer();

  /// GitHub's mark, from Octicons (MIT).
  static const _github =
      '<svg viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17'
      '.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94'
      '-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 '
      '2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82'
      '-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 '
      '0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 '
      '1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 '
      '1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/>'
      '</svg>';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return HeroCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: scheme.surface.withValues(alpha: 0.6),
                child: Text(
                  'RP',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Made by',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.72,
                        ),
                      ),
                    ),
                    Text(
                      'Rishikesh Prince Prajapati',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      '@rkprince101',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.72,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => AboutPage._open(context, Links.githubProfile),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1F2328),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
            icon: SvgPicture.string(
              _github,
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
            label: const Text('GitHub profile'),
          ),
          const SizedBox(height: 8),
          Text(
            'Other projects, updates, and the place to report a bug.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.leading,
    this.iconColor,
    this.external = false,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final Widget? leading;
  final Color? iconColor;

  /// Leaves the app, so it wears the open-in-new arrow.
  final bool external;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      leading: SizedBox(
        width: 24,
        child: Center(
          child:
              leading ??
              Icon(icon, size: 22, color: iconColor ?? colors.textMuted),
        ),
      ),
      title: Text(label),
      subtitle: detail == null ? null : Text(detail!),
      trailing: Icon(
        external ? Icons.open_in_new_rounded : Icons.chevron_right_rounded,
        size: external ? 18 : 22,
        color: colors.textMuted,
      ),
      onTap: onTap,
    );
  }
}
