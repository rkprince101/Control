import 'package:flutter/material.dart';

import '../main.dart';
import '../platform/platform_models.dart';
import 'dialogs.dart';
import 'restricted_settings.dart';

/// What Control reads, and why, said before the system screens that grant it.
///
/// An accessibility service can see a great deal, so the user hears what this
/// one reads, and agrees, before being sent to switch it on.
abstract final class Disclosures {
  static Future<void> appBlocking(BuildContext context) async {
    final agreed = await confirmAction(
      context,
      icon: Icons.accessibility_new_rounded,
      title: 'Turn on App blocking',
      message:
          'Control uses the Android Accessibility service to see which app '
          'is in front, so it can show a block screen over the apps you chose '
          'to block. For websites you block, it reads the address bar of '
          'supported browsers.',
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DialogNote(
            icon: Icons.phonelink_lock_rounded,
            text:
                'It never reads anything else in other apps, never records '
                'what you type, and nothing leaves your phone.',
          ),
          const SizedBox(height: 8),
          const DialogNote(
            icon: Icons.gpp_maybe_outlined,
            text:
                'With Hard mode on, it also reads the text of Android '
                'settings screens to notice an attempt to uninstall Control.',
          ),
        ],
      ),
      cancelLabel: 'Not now',
      confirmLabel: 'Agree',
    );
    if (agreed && context.mounted) {
      await _open(context, SpecialAccess.appBlocking);
    }
  }

  static Future<void> usageAccess(BuildContext context) async {
    final agreed = await confirmAction(
      context,
      icon: Icons.hourglass_empty_rounded,
      title: 'Allow usage access',
      message:
          'Control reads how long each app was used and how often the phone '
          'was picked up, for Insights and for rules that allow an app a set '
          'amount of time.',
      detail: const DialogNote(
        icon: Icons.phonelink_lock_rounded,
        text: 'It is worked out on this phone and never sent anywhere.',
      ),
      cancelLabel: 'Not now',
      confirmLabel: 'Agree',
    );
    if (agreed && context.mounted) {
      await _open(context, SpecialAccess.usageAccess);
    }
  }

  /// Straight to the switch, or first through the restricted-settings steps
  /// when Android is going to grey it out.
  static Future<void> _open(BuildContext context, SpecialAccess access) {
    final store = StoreScope.read(context);
    if (store.installInfo.restrictedSettingsLikely) {
      return RestrictedSettingsGuide.show(context, access);
    }
    return store.openSpecialAccess(access);
  }
}
