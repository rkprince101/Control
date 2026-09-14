import 'dart:typed_data';

import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';

import '../platform/enforcement_channel.dart';
import 'theme.dart';

/// Process-wide icon cache.
///
/// Icons are fetched one at a time over the method channel and never change
/// while the app runs, so they are held for the life of the process rather than
/// re-decoded every time a list scrolls.
class AppIconCache {
  AppIconCache._();

  static final AppIconCache instance = AppIconCache._();

  static const _channel = EnforcementChannel();
  final Map<AppId, Future<Uint8List?>> _icons = {};

  Future<Uint8List?> of(AppId id) =>
      _icons.putIfAbsent(id, () => _channel.appIcon(id));
}

class AppIcon extends StatelessWidget {
  const AppIcon({required this.id, this.size = 34, super.key});

  final AppId id;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);

    return FutureBuilder<Uint8List?>(
      future: AppIconCache.instance.of(id),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.24),
          child: bytes == null
              ? Container(
                  width: size,
                  height: size,
                  color: colors.cardRaised,
                )
              : Image.memory(
                  bytes,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
        );
      },
    );
  }
}

/// The stack of app icons on a block card: a few real icons and a count for
/// the rest, so a block over 100 apps still reads at a glance.
class AppIconCluster extends StatelessWidget {
  const AppIconCluster({required this.apps, this.size = 52, super.key});

  final Set<AppId> apps;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    final shown = apps.take(4).toList();
    final extra = apps.length - shown.length;
    final tile = size * 0.42;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: colors.cardRaised,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(4),
            child: shown.isEmpty
                ? Icon(Icons.shield_outlined, color: colors.textMuted, size: 22)
                : Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: [
                      for (final id in shown) AppIcon(id: id, size: tile),
                    ],
                  ),
          ),
          if (extra > 0)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: colors.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
