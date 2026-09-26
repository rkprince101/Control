import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../platform/platform_models.dart';
import 'sheet.dart';
import 'theme.dart';

/// Walks the user through Android's "restricted settings".
///
/// From Android 13, an app installed from a downloaded file, as every copy of
/// Control from GitHub is, has its Accessibility and Usage access switches
/// greyed out: "Controlled by restricted setting". Only the user can lift that,
/// from the app's App info, and only after tapping the greyed switch once,
/// which is not something anyone would guess. This sheet says so, one step at
/// a time, with a button for each place to go. It stays open while the user
/// is away in Settings and turns into a done state when they come back with
/// the switch on.
class RestrictedSettingsGuide extends StatelessWidget {
  const RestrictedSettingsGuide({required this.access, super.key});

  final SpecialAccess access;

  static bool _showing = false;

  /// Whether the guide is on screen, so a return from Settings does not
  /// stack a second one on top of it.
  static bool get showing => _showing;

  /// Step 2 from a computer, for anyone with adb: allows restricted settings
  /// for Control without the App info menu.
  static const adbCommand =
      'adb shell appops set com.rkprince.control ACCESS_RESTRICTED_SETTINGS '
      'allow';

  static Future<void> show(BuildContext context, SpecialAccess access) async {
    if (_showing) return;
    _showing = true;
    try {
      await showControlSheet<void>(
        context,
        builder: (_) => RestrictedSettingsGuide(access: access),
      );
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final granted = store.hasSpecialAccess(access);
    final height = MediaQuery.sizeOf(context).height;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: math.max(320, height * 0.9)),
      child: SheetScaffold(
        title: granted ? '${access.label} is on' : 'Allow ${access.label}',
        leading: SheetAction(
          granted ? 'Done' : 'Close',
          onPressed: () => Navigator.pop(context),
        ),
        child: granted
            ? _Done(access: access)
            : _Steps(access: access, install: store.installInfo),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.access, required this.install});

  final SpecialAccess access;
  final InstallInfo install;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.read(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ControlColors.of(context);
    Future<void> openSetting() => store.openSpecialAccess(access, watch: false);

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              Icons.lock_person_outlined,
              size: 30,
              color: scheme.onTertiaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Android needs one extra step',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          install.restrictedSettingsLikely
              ? 'Control was installed from a download rather than an app '
                    'store, so Android locks its ${access.screen} switch '
                    'until you allow it. It takes a minute, and only once.'
              : 'If Control\'s ${access.screen} switch is greyed out and '
                    'says "Controlled by restricted setting", Android is '
                    'holding it back because Control came from a download. '
                    'It takes a minute, and only once.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textMuted,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        _Step(
          number: 1,
          title: 'Tap Control\'s greyed-out switch once',
          body:
              'In ${access.screen}, open Control and tap its switch. Android '
              'says "Restricted setting": tap OK. This is what makes the next '
              'option appear.',
          action: 'Open ${access.screen}',
          onPressed: openSetting,
        ),
        const SizedBox(height: 10),
        _Step(
          number: 2,
          title: 'Allow restricted settings',
          body:
              'On Control\'s App info, tap # in the top corner, choose Allow '
              'restricted settings, and confirm with your PIN or fingerprint.',
          action: 'Open App info',
          onPressed: store.openAppInfo,
        ),
        const SizedBox(height: 10),
        _Step(
          number: 3,
          title: 'Turn on ${access.label}',
          body:
              'Back in ${access.screen}, switch Control on. This sheet '
              'notices when you come back.',
          action: 'Open ${access.screen}',
          onPressed: openSetting,
        ),
        const SizedBox(height: 20),
        const _AdbHint(),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    required this.action,
    required this.onPressed,
  });

  final int number;
  final String title;
  final String body;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ControlColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                // A # in the text is Android's three-dot menu, drawn as the
                // icon itself: the vertical-ellipsis character is missing
                // from some fonts.
                Text.rich(
                  TextSpan(
                    children: [
                      for (final (index, part) in body.split('#').indexed) ...[
                        if (index > 0)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(
                              Icons.more_vert_rounded,
                              size: 18,
                              color: theme.colorScheme.onSurface,
                              semanticLabel: 'the three-dot menu',
                            ),
                          ),
                        TextSpan(text: part),
                      ],
                    ],
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: Text(action),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The same thing from a computer, for anyone who has adb.
class _AdbHint extends StatefulWidget {
  const _AdbHint();

  @override
  State<_AdbHint> createState() => _AdbHintState();
}

class _AdbHintState extends State<_AdbHint> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Have a computer with adb? This does step 2 for you:',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  RestrictedSettingsGuide.adbCommand,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
              IconButton(
                tooltip: _copied ? 'Copied' : 'Copy command',
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(
                      text: RestrictedSettingsGuide.adbCommand,
                    ),
                  );
                  if (mounted) setState(() => _copied = true);
                },
                icon: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.access});

  final SpecialAccess access;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 36,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'All set',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            access == SpecialAccess.appBlocking
                ? 'Control can now put a block screen in front of the apps '
                      'and websites you choose.'
                : 'Control can now show your screen time and run app-time '
                      'rules.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ControlColors.of(context).textMuted,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
