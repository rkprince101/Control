import 'package:flutter/material.dart';

import '../main.dart';
import 'dialogs.dart';

/// What Control reads, and why, said before the system screens that grant it.
///
/// An accessibility service can see a great deal, so the user hears what this
/// one reads, and agrees, before being sent to switch it on.
abstract final class Disclosures {
  static Future<void> appBlocking(BuildContext context) async {
    final store = StoreScope.read(context);
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
          // Android 13 and later hold back accessibility for apps installed
          // from outside an app store, which is every install of Control.
          const SizedBox(height: 8),
          const DialogNote(
            icon: Icons.help_outline_rounded,
            text:
                'If Android says the setting is restricted, open App info for '
                'Control, tap ⋮, choose Allow restricted settings, then try '
                'again.',
          ),
        ],
      ),
      cancelLabel: 'Not now',
      confirmLabel: 'Agree',
    );
    if (agreed) await store.openAccessibilitySettings();
  }

  static Future<void> usageAccess(BuildContext context) async {
    final store = StoreScope.read(context);
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
    if (agreed) await store.openUsageAccessSettings();
  }
}
