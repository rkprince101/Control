import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'sheet.dart';
import 'theme.dart';

/// Where the support options and the developer's other app live.
abstract final class Links {
  static const hushroom =
      'https://play.google.com/store/apps/details?id=com.focufuse.focusage';
  static const buyMeACoffee = 'https://buymeacoffee.com/rkprince';
  static const githubProfile = 'https://github.com/rkprince101';
  static const repository = 'https://github.com/rkprince101/Control';
  static const upiId = 'rishikeshprince@upi';

  /// A UPI payment to [upiId]; the UPI app asks for the amount. Written out
  /// by hand: several UPI apps misread `+` for a space, or `%40` for the @.
  static final upiPayment = Uri.parse(
    'upi://pay?pa=$upiId&pn=Rishikesh%20Prince%20Prajapati'
    '&tn=Support%20for%20Control&cu=INR',
  );
}

/// Opens [uri] in the app that owns it (Play Store, a UPI app, the browser).
/// False when nothing on the phone can.
Future<bool> openExternal(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Hushroom's page on Google Play, or a word if it cannot be opened.
Future<void> openHushroom(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (await openExternal(Uri.parse(Links.hushroom))) return;
  messenger?.showSnackBar(
    const SnackBar(content: Text('Could not open Google Play.')),
  );
}

/// Hushroom's own art on the rounded tile a launcher would give it. The art
/// is transparent, so the tile carries its own light background in either
/// theme, as an app icon does.
class HushroomIcon extends StatelessWidget {
  const HushroomIcon({this.size = 24, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3EC),
      borderRadius: BorderRadius.circular(size * 0.28),
    ),
    clipBehavior: Clip.antiAlias,
    // The mushroom sits low and left in a lot of empty canvas: bring it to
    // the middle and let it fill the tile.
    child: Transform.scale(
      scale: 1.6,
      child: Transform.translate(
        offset: Offset(size * 0.1, -size * 0.07),
        child: Image.asset(
          'assets/hushroom.png',
          fit: BoxFit.cover,
          semanticLabel: 'Hushroom',
        ),
      ),
    ),
  );
}

/// Ways to say thanks: UPI, or Buy Me a Coffee.
class SupportSheet extends StatefulWidget {
  const SupportSheet({super.key});

  static Future<void> show(BuildContext context) =>
      showControlSheet<void>(context, builder: (_) => const SupportSheet());

  @override
  State<SupportSheet> createState() => _SupportSheetState();
}

class _SupportSheetState extends State<SupportSheet> {
  /// A line under the options: what just happened. The sheet covers the
  /// bottom of the screen, where a snackbar would be hidden.
  String? _status;

  Future<void> _copyUpiId({String? because}) async {
    await Clipboard.setData(const ClipboardData(text: Links.upiId));
    if (!mounted) return;
    setState(
      () => _status = because == null
          ? 'UPI ID copied.'
          : '$because UPI ID copied: pay it from any UPI app.',
    );
  }

  Future<void> _payWithUpi() async {
    if (await openExternal(Links.upiPayment)) return;
    await _copyUpiId(because: 'No UPI app found.');
  }

  Future<void> _buyCoffee() async {
    if (await openExternal(Uri.parse(Links.buyMeACoffee))) return;
    if (mounted) setState(() => _status = 'Could not open the browser.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ControlColors.of(context);

    return SheetScaffold(
      title: 'Support me',
      leading: SheetAction('Close', onPressed: () => Navigator.pop(context)),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                Icons.favorite_rounded,
                size: 30,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Keep Control free',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Control has no ads, no subscriptions and no tracking, and never '
            'will. If it gave you some of your time back, a small tip helps me '
            'keep making it better.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          _SupportOption(
            icon: Icons.currency_rupee_rounded,
            tint: scheme.primaryContainer,
            onTint: scheme.onPrimaryContainer,
            title: 'Pay with UPI',
            detail: Links.upiId,
            onTap: _payWithUpi,
            trailing: IconButton(
              tooltip: 'Copy UPI ID',
              onPressed: _copyUpiId,
              icon: const Icon(Icons.copy_rounded),
            ),
          ),
          const SizedBox(height: 10),
          _SupportOption(
            icon: Icons.coffee_rounded,
            tint: scheme.tertiaryContainer,
            onTint: scheme.onTertiaryContainer,
            title: 'Buy me a coffee',
            detail: 'buymeacoffee.com/rkprince',
            onTap: _buyCoffee,
            trailing: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(Icons.open_in_new_rounded, color: colors.textMuted),
            ),
          ),
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _status == null
                ? const SizedBox(width: double.infinity)
                : Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _status!,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          Text(
            'Cannot give right now? A star on GitHub, or telling a friend who '
            'needs it, helps just as much.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SupportOption extends StatelessWidget {
  const _SupportOption({
    required this.icon,
    required this.tint,
    required this.onTint,
    required this.title,
    required this.detail,
    required this.onTap,
    required this.trailing,
  });

  final IconData icon;
  final Color tint;
  final Color onTint;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: onTint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
