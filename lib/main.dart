import 'package:flutter/material.dart';

import 'state/control_store.dart';
import 'ui/block_editor_sheet.dart';
import 'ui/blocks_page.dart';
import 'ui/insights_page.dart';
import 'ui/settings_page.dart';
import 'ui/theme.dart';

void main() {
  runApp(ControlApp(store: ControlStore()));
}

class ControlApp extends StatelessWidget {
  const ControlApp({required this.store, super.key});

  final ControlStore store;

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: store,
      child: Builder(
        builder: (context) {
          final choice = StoreScope.of(context).theme;
          return MaterialApp(
            title: 'control',
            debugShowCheckedModeBanner: false,
            theme: buildControlTheme(brightness: Brightness.light),
            darkTheme: buildControlTheme(
              brightness: Brightness.dark,
              pitchBlack: choice == AppThemeChoice.pitchBlack,
            ),
            themeMode: choice.themeMode,
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}

/// Exposes the single [ControlStore] to the tree and rebuilds on every change.
class StoreScope extends InheritedNotifier<ControlStore> {
  const StoreScope({
    required ControlStore store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  static ControlStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StoreScope>();
    assert(scope?.notifier != null, 'No StoreScope above this widget');
    return scope!.notifier!;
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => StoreScope.of(context).init(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Permissions are granted on system settings screens, and habits are done
  /// while the app is closed, so returning to the app is the moment to re-read
  /// everything.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) StoreScope.of(context).refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    const pages = [BlocksPage(), InsightsPage(), SettingsPage()];

    return Scaffold(
      // The pill floats over the content: the bar slot itself paints nothing,
      // so pages scroll underneath it instead of stopping at a grey strip.
      extendBody: true,
      body: pages[_tab],
      // The primary action of the whole app, so it gets the M3 treatment
      // rather than an icon button tucked beside a heading. Only on Blocks:
      // a FAB that changes meaning per tab is worse than no FAB.
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => BlockEditorSheet.show(context),
              icon: const Icon(Icons.add),
              label: const Text('New block'),
            )
          : null,
      bottomNavigationBar: _PillNavBar(
        index: _tab,
        onChanged: (index) => setState(() => _tab = index),
      ),
    );
  }
}

/// Icons only, sized to the thumb rather than to the labels.
///
/// Three destinations that never change do not need naming on every screen:
/// the labels were repeating what the icons already said and pushing the
/// content up by a row.
/// The floating navigation pill.
///
/// Not a `NavigationBar`: that component spans the full width and reserves room
/// for labels, and this app wants the content to run underneath a small
/// floating control. The colour roles and the selected-indicator behaviour are
/// M3 all the same, including the filled-icon-when-selected convention that
/// carries the state without a label.
class _PillNavBar extends StatelessWidget {
  const _PillNavBar({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _items = [
    (Icons.shield_outlined, Icons.shield_rounded, 'Blocks'),
    (Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'Insights'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        // A Row rather than a Center: the bottom bar slot passes loose
        // constraints, and Center takes every pixel of height it is offered,
        // which leaves the body with none.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: scheme.outlineVariant, width: 0.5),
              ),
              padding: const EdgeInsets.all(5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _items.length; i++)
                    _NavItem(
                      icon: _items[i].$1,
                      selectedIcon: _items[i].$2,
                      label: _items[i].$3,
                      selected: i == index,
                      onTap: () => onChanged(i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(21);

    return Semantics(
      // The labels are gone for space, so they have to survive for screen
      // readers, which is also what makes the tabs testable by name.
      label: label,
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 62,
            height: 42,
            decoration: BoxDecoration(
              color: selected ? scheme.secondaryContainer : Colors.transparent,
              borderRadius: radius,
            ),
            child: Icon(
              selected ? selectedIcon : icon,
              size: 21,
              color: selected
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
