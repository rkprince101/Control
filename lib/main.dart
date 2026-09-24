import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'state/control_store.dart';
import 'ui/block_editor_sheet.dart';
import 'ui/blocks_page.dart';
import 'ui/expressive_progress.dart';
import 'ui/habit_sheets.dart';
import 'ui/habits_page.dart';
import 'ui/insights_page.dart';
import 'ui/navigation.dart';
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
          final store = StoreScope.of(context);
          final choice = store.theme;
          return MaterialApp(
            title: 'control',
            debugShowCheckedModeBanner: false,
            theme: buildControlTheme(brightness: Brightness.light),
            darkTheme: buildControlTheme(
              brightness: Brightness.dark,
              pitchBlack: choice == AppThemeChoice.pitchBlack,
            ),
            themeMode: choice.themeMode,
            // Above the navigator, so sheets and dialogs follow it too.
            builder: (context, child) => WaveMotionScope(
              motion: store.waveMotion,
              child: child ?? const SizedBox.shrink(),
            ),
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

/// The page's primary action: Gmail's Compose.
typedef _PageAction = ({IconData icon, String label, VoidCallback onPressed});

/// Navigation laid out the way Gmail does it.
///
/// On a phone: a search bar across the top with the menu at its left, a modal
/// drawer behind the menu, and an extended action button that tucks itself
/// away while the page scrolls. On a wide screen: a rail with the menu and the
/// action button at its head, expanding in place to show labels.
class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final _scaffold = GlobalKey<ScaffoldState>();
  Destination _destination = Destination.blocks;
  bool _fabExtended = true;
  bool _railExtended = false;

  static const _pages = {
    Destination.blocks: BlocksPage(),
    Destination.habits: HabitsPage(),
    Destination.insights: InsightsPage(),
    Destination.settings: SettingsPage(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StoreScope.of(context).init();
    });
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

  void _select(Destination destination) {
    if (destination == _destination) return;
    setState(() {
      _destination = destination;
      _fabExtended = true;
    });
  }

  /// A pick from the drawer closes it first, as every modal drawer does.
  void _selectFromDrawer(Destination destination) {
    _scaffold.currentState?.closeDrawer();
    _select(destination);
  }

  void _openDrawer() => _scaffold.currentState?.openDrawer();

  bool _onScroll(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final atTop =
        notification.metrics.pixels <= notification.metrics.minScrollExtent;
    final extended = switch (notification.direction) {
      ScrollDirection.reverse => atTop,
      ScrollDirection.forward => true,
      ScrollDirection.idle => _fabExtended || atTop,
    };
    if (extended != _fabExtended) setState(() => _fabExtended = extended);
    return false;
  }

  _PageAction? get _action => switch (_destination) {
    Destination.blocks => (
      icon: Icons.add,
      label: 'New block',
      onPressed: () => BlockEditorSheet.show(context),
    ),
    Destination.habits => (
      icon: Icons.add,
      label: 'New habit',
      onPressed: () => HabitEditorSheet.show(context),
    ),
    Destination.insights || Destination.settings => null,
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final action = _action;

    final content = NotificationListener<UserScrollNotification>(
      onNotification: _onScroll,
      child: IndexedStack(
        index: Destination.values.indexOf(_destination),
        children: [
          for (final destination in Destination.values)
            TickerMode(
              enabled: destination == _destination,
              child: _pages[destination]!,
            ),
        ],
      ),
    );

    // As in Gmail, back from any other page returns to the first one before
    // it leaves the app.
    return PopScope(
      canPop: _destination == Destination.blocks,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(Destination.blocks);
      },
      child: HomeNavigation(
        destination: _destination,
        onSelect: _select,
        onOpenDrawer: wide ? null : _openDrawer,
        child: Scaffold(
          key: _scaffold,
          drawer: wide
              ? null
              : ControlDrawer(
                  selected: _destination,
                  onSelect: _selectFromDrawer,
                  onOpenRule: (block) {
                    _scaffold.currentState?.closeDrawer();
                    BlockEditorSheet.show(context, existing: block);
                  },
                  onNewRule: () {
                    _scaffold.currentState?.closeDrawer();
                    BlockEditorSheet.show(context);
                  },
                ),
          // The search bar floats over content, so the status bar keeps its own
          // band of background rather than letting cards slide up under it.
          body: SafeArea(
            bottom: false,
            child: wide
                ? Row(
                    children: [
                      _Rail(
                        selected: _destination,
                        extended: _railExtended,
                        action: action,
                        onToggle: () =>
                            setState(() => _railExtended = !_railExtended),
                        onSelect: _select,
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: content),
                    ],
                  )
                : content,
          ),
          floatingActionButton: wide || action == null
              ? null
              : CollapsingFab(
                  extended: _fabExtended,
                  icon: action.icon,
                  label: action.label,
                  onPressed: action.onPressed,
                ),
        ),
      ),
    );
  }
}

/// Gmail's tablet layout: the menu and the primary action at the head of the
/// rail, destinations below.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.selected,
    required this.extended,
    required this.action,
    required this.onToggle,
    required this.onSelect,
  });

  final Destination selected;
  final bool extended;
  final _PageAction? action;
  final VoidCallback onToggle;
  final ValueChanged<Destination> onSelect;

  static const _collapsedWidth = 80.0;
  static const _extendedWidth = 280.0;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final action = this.action;

    return NavigationRail(
      extended: extended,
      minWidth: _collapsedWidth,
      minExtendedWidth: _extendedWidth,
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      selectedIndex: Destination.values.indexOf(selected),
      onDestinationSelected: (index) => onSelect(Destination.values[index]),
      leading: RailHead(
        extended: extended,
        onToggle: onToggle,
        collapsedWidth: _collapsedWidth,
        extendedWidth: _extendedWidth,
        icon: action?.icon,
        label: action?.label,
        onPressed: action?.onPressed,
      ),
      destinations: [
        for (final destination in Destination.values)
          NavigationRailDestination(
            icon: _badged(store, destination, Icon(destination.icon)),
            selectedIcon: _badged(
              store,
              destination,
              Icon(destination.selectedIcon),
            ),
            label: Text(destination.label),
          ),
      ],
    );
  }

  /// Counts only: a rail badge has room for a number, not a duration.
  static Widget _badged(
    ControlStore store,
    Destination destination,
    Widget icon,
  ) {
    final badge = destination == Destination.insights
        ? null
        : ControlDrawer.badgeFor(store, destination);
    return badge == null ? icon : Badge(label: Text(badge), child: icon);
  }
}
