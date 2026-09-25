/// The privacy policy and terms of use, as the app shows them.
///
/// `PRIVACY.md` and `TERMS.md` at the root of the repository say the same
/// thing for GitHub; a change to one belongs in the other.
class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.updated,
    required this.summary,
    required this.sections,
  });

  final String title;
  final String updated;

  /// The short version, shown first.
  final String summary;
  final List<LegalSection> sections;
}

class LegalSection {
  const LegalSection(this.heading, this.paragraphs, {this.points = const []});

  final String heading;
  final List<String> paragraphs;

  /// A list after the paragraphs: each point is a bold lead and its text.
  final List<(String, String)> points;
}

const _updated = '25 September 2026';
const _repository = 'github.com/rkprince101/Control';

const privacyPolicy = LegalDocument(
  title: 'Privacy policy',
  updated: _updated,
  summary:
      'Control has no accounts, no ads, no analytics and no servers. '
      'Everything it knows about you stays on your phone. The only time it '
      'uses the internet is to load map tiles when you pick a place on a map.',
  sections: [
    LegalSection(
      'What Control reads, and why',
      [
        'Control reads only what a feature you turned on needs, and only on '
            'your phone.',
      ],
      points: [
        (
          'Which app is on screen',
          'Through the Accessibility service, to show a block screen in front '
              'of the apps you chose to block. Not stored.',
        ),
        (
          'Browser address bars',
          'Through the Accessibility service, in supported browsers, to block '
              'the websites you chose to block. Not stored.',
        ),
        (
          'Android Settings screens',
          'Only while Hard mode is on, to notice an attempt to uninstall or '
              'disable Control and leave that screen. Not stored.',
        ),
        (
          'App usage and pickups',
          'Through Usage access, for Insights and for rules that allow an app '
              'a set amount of time. Kept on the phone.',
        ),
        (
          'Installed apps',
          'So you can pick which apps a rule blocks. Kept on the phone.',
        ),
        (
          'Steps',
          'Through the physical activity permission, for rules that unlock '
              'after a number of steps. Kept on the phone.',
        ),
        (
          'Location, once',
          'Only when you tap Check in on a place rule, and only while the app '
              'is open. No background location and no location history.',
        ),
      ],
    ),
    LegalSection('What Control never reads', [
      'What you type in other apps, your messages, or anything else on '
          'screen beyond the list above.',
    ]),
    LegalSection('What Control stores', [
      'Your rules, locks, habits, todos, notes, money entries, budgets, loans, '
          'focus sessions and settings are saved in the app\'s private storage '
          'on your phone. A page-lock PIN or block password is stored only as '
          'a salted hash, never as itself.',
      'None of it is sent to the developer or anyone else, and none of it is '
          'backed up to a server. Uninstalling Control, or clearing its data '
          'in Android Settings, deletes all of it.',
    ]),
    LegalSection('The internet', [
      'When you pick a place for a location rule, the map is drawn from tiles '
          'downloaded from OpenStreetMap. Their servers receive your IP '
          'address and the area you are looking at, as with any website, '
          'under the OpenStreetMap Foundation\'s privacy policy. Nothing else '
          'in the app uses the internet.',
    ]),
    LegalSection('Device admin and device owner', [
      'If you turn it on, Control can hold device admin so Android asks for '
          'an extra step before uninstalling it. If you set it up yourself '
          'over adb, it can be device owner, which lets it block its own '
          'uninstall and some system settings while your blocks are locked. '
          'It declares no device admin policies: it cannot wipe, lock or read '
          'your device. Both can be released from inside the app.',
    ]),
    LegalSection('Notifications', [
      'The focus timer, habit reminders and the weekly report are '
          'notifications made on the phone. No push service is involved.',
    ]),
    LegalSection('Sharing and selling', [
      'Control does not share, sell or transfer any data to anyone, and does '
          'not use it for advertising.',
    ]),
    LegalSection('Children', [
      'Control is not directed at children under 13 and does not knowingly '
          'process their data.',
    ]),
    LegalSection('Changes and contact', [
      'A changed policy is published with the app and at $_repository, with a '
          'new date at the top. Questions are welcome as an issue on '
          '$_repository.',
    ]),
  ],
);

const termsOfUse = LegalDocument(
  title: 'Terms of use',
  updated: _updated,
  summary:
      'Control is a free, open-source hobby project, given as it is, to help '
      'you spend less time on your phone. Using it means accepting these '
      'terms. It is a commitment device, not a guarantee.',
  sections: [
    LegalSection('The app and its licence', [
      'Control is free and open source under the MIT licence. You may use, '
          'copy, change and share it under that licence, which is in the '
          'repository at $_repository.',
      'The official builds are published only in that repository\'s '
          'releases. A copy from anywhere else may have been changed.',
    ]),
    LegalSection('Using it', [
      'You agree to use Control on your own device, or on a device whose '
          'owner has agreed to it. Do not use it to watch, restrict or '
          'control another person without their knowledge and consent.',
    ]),
    LegalSection(
      'Locks are meant to hold',
      [
        'Several features are designed to be hard to undo, because that is '
            'what makes them work. Choose them knowingly.',
      ],
      points: [
        (
          'Timed locks',
          'Cannot be opened early by any password. Only emergency unlocks '
              'break them, and those never refill.',
        ),
        (
          'Hard mode',
          'Closes the Android screens used to uninstall or disable Control '
              'while it is on.',
        ),
        (
          'Device owner',
          'Set up by you over adb. It can block uninstalling Control, force '
              'stop, safe mode, debugging, new users, factory reset from '
              'Settings and clock changes while your blocks are locked. If '
              'you lose access to the app\'s release path, removing it may '
              'take a factory reset, which erases the phone.',
        ),
      ],
    ),
    LegalSection('What Control does not promise', [
      'Blocking depends on Android and on permissions you can take back. Safe '
          'mode, turning off the Accessibility service, some manufacturers\' '
          'battery settings and future Android versions can get past it or '
          'stop it working.',
      'Habit, focus and money figures are for your own reflection. They are '
          'not medical, psychological or financial advice.',
    ]),
    LegalSection('No warranty', [
      'Control is provided "as is", without warranty of any kind, express or '
          'implied, including fitness for a particular purpose. To the '
          'fullest extent the law allows, the developer is not liable for any '
          'loss or damage from using it, including lost data, a device that '
          'needs resetting, or anything missed while an app was blocked.',
    ]),
    LegalSection('Your data', [
      'Everything you enter stays on your phone, as the privacy policy '
          'describes. Keeping a copy of anything important is up to you.',
    ]),
    LegalSection('Changes and contact', [
      'These terms may change with a new release; the date at the top says '
          'when. Questions are welcome as an issue on $_repository.',
    ]),
  ],
);
