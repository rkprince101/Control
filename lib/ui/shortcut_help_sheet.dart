import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sheet.dart';
import 'theme.dart';

/// Explains what a shortcut channel is and how to fire one.
///
/// The feature is powerful and completely opaque until someone tells you that
/// "channel" just means a name you invent, so the explanation lives one tap
/// from the field rather than in a manual nobody opens.
class ShortcutHelpSheet extends StatelessWidget {
  const ShortcutHelpSheet({required this.channel, super.key});

  /// The channel being configured, so every example is copy-pasteable as is.
  final String channel;

  static Future<void> show(BuildContext context, String channel) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ControlColors.of(context).background,
      builder: (_) => ShortcutHelpSheet(
        channel: channel.trim().isEmpty ? 'pushups' : channel.trim().toLowerCase(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    final link = 'control://shortcut?channel=$channel';

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Column(
        children: [
            const SheetGrabber(),
          SheetHeader(
            title: 'Shortcuts',
            leading: SheetAction(
              'Done',
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                const Text(
                  'How shortcuts work',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  'A channel is a name you invent for one real-world action: '
                  '"pushups", "cold-shower", "desk". Control does not know how '
                  'you did it and does not try to. It only counts how many '
                  'times the name was fired today.\n\n'
                  'That is the whole trick. Anything on your phone that can '
                  'open a link or send a broadcast can vouch for a habit, so '
                  'the proof can be something physical you have to walk to.',
                  style: TextStyle(color: colors.textMuted, height: 1.5),
                ),
                const SizedBox(height: 24),
                _Section(
                  number: '1',
                  title: 'NFC tag',
                  body: 'The strongest version, because the tag lives '
                      'somewhere you have to physically go. Buy NTAG215 '
                      'stickers, install any NFC writer app, and write this '
                      'as a URI record. Stick it on the gym bag, the yoga '
                      'mat, the kitchen wall. Tapping your phone on it counts '
                      'one.',
                  code: link,
                ),
                _Section(
                  number: '2',
                  title: 'Home-screen shortcut or QR code',
                  body: 'Any app that makes a link shortcut works: put the '
                      'same URL behind an icon, or print it as a QR code and '
                      'tape it where the habit happens. Scanning it with the '
                      'camera counts one.',
                  code: link,
                ),
                _Section(
                  number: '3',
                  title: 'Automation app',
                  body: 'MacroDroid, Tasker, or Automate can fire a channel '
                      'when something else happens: a workout app finishing, '
                      'a smart scale syncing, arriving at the library. Add a '
                      '"Send broadcast" action with this action name and a '
                      'string extra called channel.',
                  code: 'com.rkprince.control.action.SHORTCUT\n'
                      'extra: channel = $channel',
                ),
                _Section(
                  number: '4',
                  title: 'From a computer, for testing',
                  body: 'Useful while you are setting this up, before the tag '
                      'arrives.',
                  code: 'adb shell am broadcast '
                      '-a com.rkprince.control.action.SHORTCUT '
                      '--es channel $channel',
                ),
                const SizedBox(height: 8),
                _Rules(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.number,
    required this.title,
    required this.body,
    required this.code,
  });

  final String number;
  final String title;
  final String body;
  final String code;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.light.withValues(alpha: 0.16),
                ),
                child: Text(
                  number,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.light,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: TextStyle(color: colors.textMuted, height: 1.45)),
          const SizedBox(height: 10),
          _Code(code: code),
        ],
      ),
    );
  }
}

class _Code extends StatelessWidget {
  const _Code({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);

    return GestureDetector(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: code));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copied')),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                code,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.copy_rounded, size: 15, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _Rules extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Worth knowing',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          for (final line in const [
            'Counts reset at midnight, like every other habit.',
            'Names are matched loosely, so "Pushups" and "pushups" are the '
                'same channel.',
            'Nothing stops you firing a tag ten times from the sofa. The '
                'point is that walking to it is easier than lying to '
                'yourself, not that it cannot be cheated.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: TextStyle(color: colors.textMuted)),
                  Expanded(
                    child: Text(
                      line,
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
