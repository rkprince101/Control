import 'package:control_core/control_core.dart';

/// Curated bundles for the app picker.
///
/// Building a "Social" block by hand is forty taps through an alphabetical list
/// of two hundred apps, and the one you forget is the one you open. A preset
/// turns it into two.
///
/// Package names rather than categories: Android has no reliable category for
/// this. Play Store categories are self-declared, put X under News, and are not
/// exposed to apps at all on most versions. A hand-kept list is smaller than
/// people expect and never surprises anyone.
class AppGroup {
  const AppGroup({
    required this.name,
    required this.packages,
    required this.domains,
  });

  final String name;

  /// Only the ones actually installed are ever added, so a list covering every
  /// regional variant costs nothing on a device that has none of them.
  final Set<AppId> packages;

  /// The web equivalents, added to the block at the same time. Blocking the app
  /// and leaving the site open is the loophole this pairing exists to close.
  final Set<String> domains;

  static const all = [social, video, news, games, shopping, messaging];

  static const social = AppGroup(
    name: 'Social',
    packages: {
      'com.instagram.android',
      'com.instagram.lite',
      'com.zhiliaoapp.musically', // TikTok
      'com.ss.android.ugc.trill', // TikTok, some regions
      'com.twitter.android',
      'com.facebook.katana',
      'com.facebook.lite',
      'com.snapchat.android',
      'com.reddit.frontpage',
      'com.linkedin.android',
      'com.pinterest',
      'com.tumblr',
      'app.bsky', // Bluesky
      'com.instagram.barcelona', // Threads
    },
    domains: {
      'instagram.com',
      'tiktok.com',
      'x.com',
      'twitter.com',
      'facebook.com',
      'reddit.com',
      'linkedin.com',
      'pinterest.com',
      'threads.net',
      'snapchat.com',
    },
  );

  static const video = AppGroup(
    name: 'Video',
    packages: {
      'com.google.android.youtube',
      'com.google.android.apps.youtube.music',
      'com.netflix.mediaclient',
      'com.amazon.avod.thirdpartyclient',
      'com.disney.disneyplus',
      'in.startv.hotstar',
      'com.crunchyroll.crunchyroid',
      'tv.twitch.android.app',
      'com.spotify.music',
    },
    domains: {
      'youtube.com',
      'netflix.com',
      'primevideo.com',
      'hotstar.com',
      'twitch.tv',
      'crunchyroll.com',
    },
  );

  static const news = AppGroup(
    name: 'News',
    packages: {
      'com.google.android.apps.magazines', // Google News
      'flipboard.app',
      'com.medium.reader',
      'com.ycombinator.hackernews',
      'bbc.mobile.news.ww',
      'com.cnn.mobile.android.phone',
    },
    domains: {
      'news.google.com',
      'news.ycombinator.com',
      'medium.com',
      'bbc.co.uk',
      'cnn.com',
    },
  );

  static const games = AppGroup(
    name: 'Games',
    packages: {
      'com.supercell.clashofclans',
      'com.supercell.brawlstars',
      'com.dts.freefireth',
      'com.pubg.imobile',
      'com.activision.callofduty.shooter',
      'com.king.candycrushsaga',
      'com.mojang.minecraftpe',
      'com.roblox.client',
    },
    domains: {'roblox.com', 'poki.com', 'crazygames.com'},
  );

  static const shopping = AppGroup(
    name: 'Shopping',
    packages: {
      'com.amazon.mShop.android.shopping',
      'com.flipkart.android',
      'com.einnovation.temu',
      'com.zzkko', // Shein
      'com.ebay.mobile',
      'com.myntra.android',
    },
    domains: {'amazon.com', 'flipkart.com', 'temu.com', 'shein.com', 'ebay.com'},
  );

  static const messaging = AppGroup(
    name: 'Messaging',
    packages: {
      'com.whatsapp',
      'org.telegram.messenger',
      'com.discord',
      'com.facebook.orca',
      'com.Slack',
    },
    domains: {'web.whatsapp.com', 'web.telegram.org', 'discord.com'},
  );

  /// The members of this group that are actually on the device.
  Set<AppId> installedFrom(Iterable<AppId> installed) {
    final present = installed.toSet();
    return packages.where(present.contains).toSet();
  }
}
