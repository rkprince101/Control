import 'package:flutter/material.dart';

import 'theme.dart';

/// What the computer needs before any of the provisioning commands work.
///
/// The command on its own is useless advice. `adb` is not on a normal machine,
/// and on Windows a missing OEM driver means the phone never appears at all, so
/// the command fails with "no devices found" and the user has no idea why.
///
/// Wireless debugging is listed first on purpose: it is the one route that is
/// identical on Samsung, Xiaomi, Pixel and everything else, because it never
/// touches a USB driver. Chasing a manufacturer driver is the fallback, not the
/// starting point.
class AdbPrerequisitesCard extends StatelessWidget {
  const AdbPrerequisitesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.laptop_rounded, color: colors.textMuted),
          title: const Text(
            'What you need on the computer',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Text(
            'adb is not installed by default',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          children: const [
            _Prereq(
              title: 'Android SDK Platform Tools',
              body: 'The official package that contains adb. Free, no account '
                  'needed, around 15 MB. Download the build for your operating '
                  'system and unzip it anywhere. This part is needed either '
                  'way.',
              detail: 'developer.android.com/tools/releases/platform-tools',
            ),
            _Prereq(
              title: 'A terminal open in that folder',
              body: 'On Windows, shift-right-click inside the unzipped folder '
                  'and choose Open PowerShell window here, then type .\\adb '
                  'instead of adb. On macOS and Linux, cd into the folder and '
                  'use ./adb.',
            ),
            _Section('The easy route: no driver at all'),
            _Prereq(
              title: 'Wireless debugging, Android 11 and up',
              body: 'Works the same on every make, because no USB driver is '
                  'involved. Put the phone and the computer on the same Wi-Fi, '
                  'then in Developer options turn on Wireless debugging and '
                  'open Pair device with pairing code. It shows an address and '
                  'a six-digit code.',
            ),
            _Prereq(
              title: 'Pair, then connect',
              body: 'Run adb pair with the address from the pairing dialog and '
                  'enter the code. Then run adb connect with the address from '
                  'the main Wireless debugging screen, which uses a different '
                  'port. After that every adb command works as if it were '
                  'plugged in.',
              detail: 'adb pair 192.168.1.20:37419\nadb connect 192.168.1.20:35291',
            ),
            _Section('If you use a USB cable instead'),
            _Prereq(
              title: 'Set the USB mode to File transfer',
              body: 'Pull down the notification shade after plugging in and '
                  'change it from Charging to File transfer or MTP. On many '
                  'phones adb is invisible in charging mode, and this alone '
                  'fixes most cases of a phone that never appears.',
            ),
            _Prereq(
              title: 'Windows only: point the driver at Android ADB Interface',
              body: 'This is the manufacturer-independent method. Open Device '
                  'Manager, find the phone, usually with a yellow warning under '
                  'Other devices, then Update driver, Browse my computer, Let '
                  'me pick from a list, and choose Android Device followed by '
                  'Android ADB Interface. macOS and Linux need none of this.',
            ),
            _Prereq(
              title: 'Windows only: the Google USB Driver, if that list is empty',
              body: 'Install it from Android Studio, SDK Manager, SDK Tools '
                  'tab, Google USB Driver. Then repeat the step above and use '
                  'Browse to point at the folder it was installed into.',
              detail: r'%LOCALAPPDATA%\Android\Sdk\extras\google\usb_driver',
            ),
            _Prereq(
              title: 'Manufacturer drivers, as a last resort',
              body: 'Samsung: Samsung USB Driver for Mobile Phones, or install '
                  'Smart Switch, which bundles it. Xiaomi and Redmi and Poco: '
                  'Mi USB Driver, bundled with the Mi Flash Tool. Huawei: '
                  'HiSuite. Oppo, realme, OnePlus and vivo usually work with '
                  'the Google driver above. Get these from the maker support '
                  'site, never from a driver-pack site.',
            ),
            _Prereq(
              title: 'A data USB cable',
              body: 'Some cheap cables carry power only. If the phone charges '
                  'but never shows up, try a different cable before installing '
                  'anything.',
              last: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 14),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            color: ControlColors.of(context).textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      );
}

class _Prereq extends StatelessWidget {
  const _Prereq({
    required this.title,
    required this.body,
    this.detail,
    this.last = false,
  });

  final String title;
  final String body;
  final String? detail;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 15, top: 4),
            child: Text(
              body,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(left: 15, top: 6),
              child: SelectableText(
                detail!,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.5,
                  color: colors.light,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
