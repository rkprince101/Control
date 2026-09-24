import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_icons.dart';
import 'controls.dart';
import 'sheet.dart';
import 'theme.dart';

/// The tile at the left of a block card.
///
/// A chosen icon wins over the app icons: a block called "Good night" covering
/// 125 apps is recognised by its moon, not by whichever four icons happened to
/// sort first.
class BlockIcon extends StatelessWidget {
  const BlockIcon({required this.block, this.size = 52, super.key});

  final Block block;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = block.iconAsset;
    if (asset == null) return AppIconCluster(apps: block.apps, size: size);

    return BlockIconTile(asset: asset, size: size);
  }
}

class BlockIconTile extends StatelessWidget {
  const BlockIconTile({required this.asset, this.size = 52, this.tint, super.key});

  final String asset;
  final double size;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    final foreground = tint ?? Theme.of(context).colorScheme.onSurface;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.cardRaised,
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      padding: EdgeInsets.all(size * 0.22),
      child: SvgPicture.asset(
        asset,
        colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
        // The bundled icons are drawn white; without this they vanish on the
        // light theme.
        placeholderBuilder: (_) => const SizedBox.shrink(),
      ),
    );
  }
}

/// Grid picker over the bundled icon set.
class IconPickerSheet extends StatefulWidget {
  const IconPickerSheet({required this.selected, super.key});

  final String? selected;

  /// Returns the chosen asset path, an empty string to clear, or null when
  /// dismissed. The three cases are distinct: dismissing must not clear.
  static Future<String?> show(BuildContext context, String? selected) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ControlColors.of(context).background,
      builder: (_) => IconPickerSheet(selected: selected),
    );
  }

  @override
  State<IconPickerSheet> createState() => _IconPickerSheetState();
}

class _IconPickerSheetState extends State<IconPickerSheet> {
  static const _general = 'assets/icons/';
  static const _habits = 'assets/icons/habits/';

  List<String>? _all;
  String _query = '';
  bool _habitsOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reads the bundle manifest rather than hard-coding 400 paths, so dropping
  /// a new SVG into `assets/icons/` is all it takes to add one.
  Future<void> _load() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest
        .listAssets()
        .where((path) => path.startsWith(_general) && path.endsWith('.svg'))
        .toList()
      ..sort();
    if (mounted) setState(() => _all = assets);
  }

  List<String> get _visible {
    final all = _all ?? const <String>[];
    final query = _query.trim().toLowerCase();

    return all.where((path) {
      final isHabit = path.startsWith(_habits);
      if (_habitsOnly != isHabit) return false;
      if (query.isEmpty) return true;
      return _label(path).contains(query);
    }).toList();
  }

  /// Filenames carry a random suffix from the export tool
  /// (`book-open-bkvs82d7-.svg`), so search matches the readable part only.
  static String _label(String path) {
    final name = path.split('/').last.replaceAll('.svg', '');
    return name.replaceAll(RegExp(r'-[a-z0-9]{8}-$'), '').toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Column(
        children: [
          const SheetGrabber(),
          SheetHeader(
            title: 'Icon',
            leading: SheetAction(
              'Cancel',
              onPressed: () => Navigator.pop(context),
            ),
            trailing: SheetAction(
              'Clear',
              onPressed: () => Navigator.pop(context, ''),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Search icons',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: colors.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ControlSegmented<bool>(
                  compact: true,
                  value: _habitsOnly,
                  options: const [(false, 'Icons'), (true, 'Habits')],
                  onChanged: (value) => setState(() => _habitsOnly = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _all == null
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                    itemCount: _visible.length,
                    itemBuilder: (context, index) {
                      final asset = _visible[index];
                      final isSelected = asset == widget.selected;

                      return GestureDetector(
                        onTap: () => Navigator.pop(context, asset),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? colors.light
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: BlockIconTile(asset: asset, size: 56),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
