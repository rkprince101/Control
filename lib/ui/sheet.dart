import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sheet chrome modelled on the iOS sheet, because Flutter's is wasteful.
///
/// `showDragHandle` reserves a full 48dp touch band and centres a handle in it,
/// so roughly 22dp of dead space sits between the handle and whatever comes
/// next. Stack a header row under that and the top of every sheet is an inch of
/// nothing.
///
/// iOS does the same job in about 18pt: a 36x5 grabber a few points below the
/// top edge, then content immediately, then a 44pt navigation row holding
/// Cancel, a title, and the confirming action. That is what this reproduces.
/// The grabber is still a real drag target, it just does not reserve a band it
/// does not need.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    required this.child,
    this.title,
    this.leading,
    this.trailing,
    this.heightFactor,
    super.key,
  });

  final Widget child;
  final String? title;
  final Widget? leading;
  final Widget? trailing;

  /// Fraction of the screen the sheet occupies. Null lets it size to content,
  /// which is what a short sheet should do.
  final double? heightFactor;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetGrabber(),
        if (title != null || leading != null || trailing != null)
          SheetHeader(title: title, leading: leading, trailing: trailing),
        if (heightFactor != null)
          Expanded(child: child)
        else
          Flexible(child: child),
      ],
    );

    if (heightFactor == null) return content;
    return FractionallySizedBox(heightFactor: heightFactor, child: content);
  }
}

/// 36x4, a few points below the top edge, and nothing else.
class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 6),
    child: Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// The navigation row under the grabber: an action on the left, a centred
/// title, and an optional confirming action on the right.
///
/// The title is centred rather than leading-aligned because the two actions
/// flank it, and a leading title with two buttons beside it reads as three
/// competing items rather than as a bar. It stays centred for as long as it
/// fits between the actions, then gives way rather than overlapping them.
///
/// A sheet with a single action puts it on the left, where every other sheet
/// keeps its way out, so the eye never has to hunt for it.
class SheetHeader extends StatelessWidget {
  const SheetHeader({this.title, this.leading, this.trailing, super.key});

  final String? title;
  final Widget? leading;
  final Widget? trailing;

  /// Kept clear of the sheet's rounded top corners.
  static const inset = 16.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Tall enough for a pill at any text size, without a fixed 44pt band
    // clipping it at 2x.
    final height = MediaQuery.textScalerOf(context).scale(20) + 36;

    return Padding(
      padding: const EdgeInsets.fromLTRB(inset, 2, inset, 6),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomMultiChildLayout(
          delegate: _HeaderLayout(Directionality.of(context)),
          children: [
            if (leading != null)
              LayoutId(id: _HeaderSlot.leading, child: leading!),
            if (title != null)
              LayoutId(
                id: _HeaderSlot.title,
                child: Semantics(
                  header: true,
                  child: Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            if (trailing != null)
              LayoutId(id: _HeaderSlot.trailing, child: trailing!),
          ],
        ),
      ),
    );
  }
}

enum _HeaderSlot { leading, title, trailing }

class _HeaderLayout extends MultiChildLayoutDelegate {
  _HeaderLayout(this.direction);

  final TextDirection direction;

  static const _gap = 8.0;

  @override
  void performLayout(Size size) {
    final side = BoxConstraints.loose(Size(size.width * 0.45, size.height));
    var start = Size.zero;
    var end = Size.zero;
    if (hasChild(_HeaderSlot.leading)) {
      start = layoutChild(_HeaderSlot.leading, side);
    }
    if (hasChild(_HeaderSlot.trailing)) {
      end = layoutChild(_HeaderSlot.trailing, side);
    }
    final ltr = direction == TextDirection.ltr;
    double centreY(Size child) => (size.height - child.height) / 2;

    if (hasChild(_HeaderSlot.leading)) {
      positionChild(
        _HeaderSlot.leading,
        Offset(ltr ? 0 : size.width - start.width, centreY(start)),
      );
    }
    if (hasChild(_HeaderSlot.trailing)) {
      positionChild(
        _HeaderSlot.trailing,
        Offset(ltr ? size.width - end.width : 0, centreY(end)),
      );
    }
    if (hasChild(_HeaderSlot.title)) {
      final before = start.width == 0 ? 0.0 : start.width + _gap;
      final after = end.width == 0 ? 0.0 : end.width + _gap;
      final room = math.max(0.0, size.width - before - after);
      final title = layoutChild(
        _HeaderSlot.title,
        BoxConstraints(maxWidth: room, maxHeight: size.height),
      );
      // Centred on the sheet when it fits, otherwise nudged clear of the
      // wider action.
      final leftEdge = ltr ? before : after;
      final rightEdge = size.width - (ltr ? after : before);
      final x = ((size.width - title.width) / 2)
          .clamp(leftEdge, math.max(leftEdge, rightEdge - title.width))
          .toDouble();
      positionChild(_HeaderSlot.title, Offset(x, centreY(title)));
    }
  }

  @override
  bool shouldRelayout(_HeaderLayout oldDelegate) =>
      direction != oldDelegate.direction;
}

/// A header action: the label inside a rounded, tonal container.
///
/// The confirming action is filled with the primary container, the way out
/// with a quieter surface tone, so the two read apart at a glance. Still a
/// [TextButton] underneath, with its 48dp touch target and semantics.
class SheetAction extends StatelessWidget {
  const SheetAction(
    this.label, {
    required this.onPressed,
    this.primary = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: primary
            ? scheme.primaryContainer
            : scheme.surfaceContainerHigh,
        foregroundColor: primary ? scheme.onPrimaryContainer : scheme.onSurface,
        disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.06),
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
        minimumSize: const Size(64, 40),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        shape: const StadiumBorder(),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Opens a sheet with the app chrome, and without Flutter's handle band.
Future<T?> showControlSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool transparent = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: transparent
        ? Colors.transparent
        : Theme.of(context).colorScheme.surface,
    // Every sheet draws its own grabber, at iOS proportions.
    showDragHandle: false,
    builder: builder,
  );
}
