import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';

import '../data/app_groups.dart';
import '../main.dart';
import '../platform/platform_models.dart';
import 'controls.dart';
import 'app_icons.dart';
import 'sheet.dart';
import 'theme.dart';

/// What the picker hands back.
///
/// Carries domains as well as apps because the presets know both: adding
/// "Social" and leaving instagram.com open would rebuild the loophole the site
/// list exists to close.
class AppSelection {
  const AppSelection({
    required this.apps,
    this.domains = const {},
    this.categories = const {},
    this.excludedApps = const {},
  });

  final Set<AppId> apps;
  final Set<String> domains;
  final Set<String> categories;
  final Set<AppId> excludedApps;
}

/// Multi-select app list backed by the launchable apps the platform reports.
///
/// Returns null when dismissed, so a cancelled sheet never clears a selection
/// the user already made.
class AppPickerSheet extends StatefulWidget {
  const AppPickerSheet({
    required this.initialSelection,
    this.locked = const {},
    this.allowCategories = false,
    this.initialCategories = const {},
    this.initialExcludedApps = const {},
    this.lockedCategories = const {},
    this.categoryRulesLocked = false,
    super.key,
  });

  final Set<AppId> initialSelection;

  /// Apps that cannot be unchecked, because the block they belong to is locked.
  /// Adding more is still allowed: a lock stops you weakening a rule, not
  /// tightening it.
  final Set<AppId> locked;
  final bool allowCategories;
  final Set<String> initialCategories;
  final Set<AppId> initialExcludedApps;
  final Set<String> lockedCategories;

  /// Locked rules may remove exclusions, but cannot add any.
  final bool categoryRulesLocked;

  static Future<AppSelection?> show(
    BuildContext context,
    Set<AppId> initialSelection, {
    Set<AppId> locked = const {},
    bool allowCategories = false,
    Set<String> initialCategories = const {},
    Set<AppId> initialExcludedApps = const {},
    Set<String> lockedCategories = const {},
    bool categoryRulesLocked = false,
  }) {
    return showModalBottomSheet<AppSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ControlColors.of(context).background,
      builder: (_) => AppPickerSheet(
        initialSelection: initialSelection,
        locked: locked,
        allowCategories: allowCategories,
        initialCategories: initialCategories,
        initialExcludedApps: initialExcludedApps,
        lockedCategories: lockedCategories,
        categoryRulesLocked: categoryRulesLocked,
      ),
    );
  }

  @override
  State<AppPickerSheet> createState() => _AppPickerSheetState();
}

class _AppPickerSheetState extends State<AppPickerSheet> {
  late final Set<AppId> _selected = {...widget.initialSelection};
  final Set<String> _domains = {};
  late final Set<String> _categories = widget.allowCategories
      ? {...widget.initialCategories}
      : {};
  late final Set<AppId> _excludedApps = widget.allowCategories
      ? {...widget.initialExcludedApps}
      : {};
  static const _categoryLabels = {
    'browsers': 'Browsers',
    'games': 'Games',
    'all_apps': 'All apps',
  };
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
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
    final missing = {..._selected, ..._excludedApps}
        .where((id) => !installed.contains(id))
        .map((id) => InstalledApp(id: id, label: id, isSystem: false));

    final apps = [...missing, ...store.installedApps]
        .where((app) => app.label.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            const SheetGrabber(),
            SheetHeader(
              title: widget.allowCategories
                  ? 'Apps'
                  : '${_selected.length} selected',
              leading: SheetAction(
                'Cancel',
                onPressed: () => Navigator.pop(context),
              ),
              trailing: SheetAction(
                'Done',
                primary: true,
                onPressed: () => Navigator.pop(
                  context,
                  AppSelection(
                    apps: _selected,
                    domains: _domains,
                    categories: _categories,
                    excludedApps: _excludedApps,
                  ),
                ),
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
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Detailed counts scroll rather than crowding the actions.
                        if (widget.allowCategories)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: Text(
                              '${_selected.length} apps, '
                              '${_categories.length} categories, '
                              '${_excludedApps.length} exclusions',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        if (widget.allowCategories) _categoryRules(),
                        if (widget.allowCategories)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: Text(
                              'Presets: add installed apps and sites',
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
                        if (widget.allowCategories)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Checkboxes explicitly block individual apps.',
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_loading)
                    const SliverToBoxAdapter(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    SliverList.builder(
                      itemCount: apps.length,
                      itemBuilder: (context, index) {
                        final app = apps[index];
                        final excluded = _excludedApps.contains(app.id);
                        final matches = _categories.where(
                          (category) =>
                              category != 'all_apps' &&
                              app.categories.contains(category),
                        );
                        final tile = _AppTile(
                          app: app,
                          selected: _selected.contains(app.id),
                          locked: widget.locked.contains(app.id),
                          status: !widget.allowCategories
                              ? null
                              : [
                                  if (_selected.contains(app.id))
                                    'Explicitly blocked',
                                  if (excluded) 'Excluded from categories',
                                  if (!excluded && matches.isNotEmpty)
                                    'Matches category: ${matches.map((c) => _categoryLabels[c] ?? c).join(', ')}',
                                  if (!excluded &&
                                      _categories.contains('all_apps'))
                                    'All apps rule (system safeguards apply)',
                                  if (!installed.contains(app.id))
                                    'Not installed',
                                ].join(' | '),
                          // Selection lives in this sheet, not in the tile, so
                          // the selection counter stays truthful.
                          onChanged: (checked) => setState(() {
                            if (checked) {
                              _selected.add(app.id);
                            } else {
                              _selected.remove(app.id);
                            }
                          }),
                        );
                        if (!widget.allowCategories ||
                            (_categories.isEmpty && !excluded)) {
                          return tile;
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            tile,
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 16,
                                bottom: 8,
                              ),
                              child: TextButton.icon(
                                key: ValueKey('exclude-${app.id}'),
                                icon: Icon(
                                  excluded
                                      ? Icons.undo
                                      : Icons.remove_circle_outline,
                                  size: 18,
                                ),
                                label: Text(
                                  excluded
                                      ? 'Remove category exclusion'
                                      : 'Exclude from categories',
                                ),
                                onPressed:
                                    !excluded && widget.categoryRulesLocked
                                    ? null
                                    : () => setState(() {
                                        if (excluded) {
                                          _excludedApps.remove(app.id);
                                        } else {
                                          _excludedApps.add(app.id);
                                        }
                                      }),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryRules() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Persistent categories',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in _categoryLabels.entries)
              ControlChip(
                label: entry.value,
                selected: _categories.contains(entry.key),
                icon: widget.lockedCategories.contains(entry.key)
                    ? Icons.lock
                    : null,
                onTap: () {
                  if (widget.lockedCategories.contains(entry.key)) return;
                  setState(() {
                    if (!_categories.remove(entry.key)) {
                      _categories.add(entry.key);
                    }
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Automatically covers matching apps installed later. Detection uses '
          'Android metadata and capabilities; disguised or misreported apps '
          'may escape browser/game detection. All apps is an optional stronger '
          'fallback; critical phone and system apps stay accessible.\n\n'
          'Exclusions affect only categories in this block. Explicit app '
          'blocks and other blocks still apply. '
          'Exclusions are kept even when an app is uninstalled.'
          '${widget.categoryRulesLocked ? '\n\nLocked: add categories or remove exclusions only.' : ''}',
          style: TextStyle(
            color: ControlColors.of(context).textMuted,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.selected,
    required this.onChanged,
    this.locked = false,
    this.status,
  });

  final InstalledApp app;
  final bool selected;
  final bool locked;
  final String? status;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: selected,
      enabled: !locked,
      secondary: locked
          ? Icon(Icons.lock, size: 16, color: ControlColors.of(context).medium)
          : AppIcon(id: app.id, size: 36),
      title: Text(app.label),
      subtitle: Text(
        status == null || status!.isEmpty ? app.id : '${app.id}\n$status',
        maxLines: status == null ? 1 : null,
        overflow: status == null ? TextOverflow.ellipsis : null,
        style: TextStyle(
          color: ControlColors.of(context).textMuted,
          fontSize: 12,
        ),
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
      for (final group in AppGroup.all) (group, group.installedFrom(installed)),
    ].where((entry) => entry.$2.isNotEmpty).toList();

    if (groups.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        spacing: 8,
        children: [
          for (final (group, present) in groups)
            ControlChip(
              label: '${group.name} (${present.length})',
              selected: selected.containsAll(present),
              icon: selected.containsAll(present)
                  ? Icons.check_rounded
                  : Icons.add_rounded,
              onTap: () => onAdd(present, group.domains),
            ),
        ],
      ),
    );
  }
}
