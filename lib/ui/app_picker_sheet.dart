import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';

import '../data/app_groups.dart';
import '../main.dart';
import '../platform/platform_models.dart';
import 'controls.dart';
import 'sheet.dart';
import 'theme.dart';

/// What the picker hands back.
///
/// Carries domains as well as apps because the presets know both: adding
/// "Social" and leaving instagram.com open would rebuild the loophole the site
/// list exists to close.
class AppSelection {
  const AppSelection({required this.apps, this.domains = const {}});

  final Set<AppId> apps;
  final Set<String> domains;
}

/// Multi-select app list backed by the launchable apps the platform reports.
///
/// Returns null when dismissed, so a cancelled sheet never clears a selection
/// the user already made.
class AppPickerSheet extends StatefulWidget {
  const AppPickerSheet({
    required this.initialSelection,
    this.locked = const {},
    super.key,
  });

  final Set<AppId> initialSelection;

  /// Apps that cannot be unchecked, because the block they belong to is locked.
  /// Adding more is still allowed: a lock stops you weakening a rule, not
  /// tightening it.
  final Set<AppId> locked;

  static Future<AppSelection?> show(
    BuildContext context,
    Set<AppId> initialSelection, {
    Set<AppId> locked = const {},
  }) {
    return showModalBottomSheet<AppSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ControlColors.of(context).background,
      builder: (_) => AppPickerSheet(
        initialSelection: initialSelection,
        locked: locked,
      ),
    );
  }

  @override
  State<AppPickerSheet> createState() => _AppPickerSheetState();
}

class _AppPickerSheetState extends State<AppPickerSheet> {
  late final Set<AppId> _selected = {...widget.initialSelection};
  final Set<String> _domains = {};
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await StoreScope.of(context).loadInstalledApps();
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);

    // An app that is blocked but not currently installed still belongs in the
    // list. Uninstalling Instagram does not lift the block, and hiding it here
    // would leave a rule the user can see the effects of but not edit.
    final installed = store.installedApps.map((app) => app.id).toSet();
    final missing = _selected
        .where((id) => !installed.contains(id))
        .map((id) => InstalledApp(id: id, label: id, isSystem: false));

    final apps = [...missing, ...store.installedApps]
        .where((app) => app.label.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Column(
        children: [
            const SheetGrabber(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                Text('${_selected.length} selected'),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(
                    context,
                    AppSelection(apps: _selected, domains: _domains),
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search apps',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: colors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          _Presets(
            installed: store.installedApps.map((app) => app.id),
            selected: _selected,
            onAdd: (packages, domains) => setState(() {
              _selected.addAll(packages);
              _domains.addAll(domains);
            }),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: apps.length,
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      return _AppTile(
                        app: app,
                        selected: _selected.contains(app.id),
                        locked: widget.locked.contains(app.id),
                        // Selection lives in this sheet, not in the tile, so
                        // the counter in the header stays truthful.
                        onChanged: (checked) => setState(() {
                          if (checked) {
                            _selected.add(app.id);
                          } else {
                            _selected.remove(app.id);
                          }
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.selected,
    required this.onChanged,
    this.locked = false,
  });

  final InstalledApp app;
  final bool selected;
  final bool locked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: selected,
      enabled: !locked,
      secondary: locked
          ? Icon(Icons.lock, size: 16, color: ControlColors.of(context).medium)
          : null,
      title: Text(app.label),
      subtitle: Text(
        app.id,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: ControlColors.of(context).textMuted, fontSize: 12),
      ),
      controlAffinity: ListTileControlAffinity.trailing,
      onChanged: locked ? null : (checked) => onChanged(checked ?? false),
    );
  }
}

/// One tap adds every installed member of a bundle.
///
/// Additive only: a preset never removes an app the user picked by hand, and a
/// half-matching preset is not shown as selected, because "some of Social" is
/// not a state anyone means to be in.
class _Presets extends StatelessWidget {
  const _Presets({
    required this.installed,
    required this.selected,
    required this.onAdd,
  });

  final Iterable<AppId> installed;
  final Set<AppId> selected;
  final void Function(Set<AppId> packages, Set<String> domains) onAdd;

  @override
  Widget build(BuildContext context) {
    final groups = [
      for (final group in AppGroup.all)
        (group, group.installedFrom(installed)),
    ].where((entry) => entry.$2.isNotEmpty).toList();

    if (groups.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (group, present) = groups[index];
          final complete = selected.containsAll(present);

          return ControlChip(
            label: '${group.name} (${present.length})',
            selected: complete,
            icon: complete ? Icons.check_rounded : Icons.add_rounded,
            onTap: () => onAdd(present, group.domains),
          );
        },
      ),
    );
  }
}
