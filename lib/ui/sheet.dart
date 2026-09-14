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
        if (heightFactor != null) Expanded(child: child) else Flexible(child: child),
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

/// The 44pt navigation row: a cancel on the left, a centred title, a
/// confirming action on the right.
///
/// The title is centred rather than leading-aligned because the two actions
/// flank it, and a leading title with two buttons beside it reads as three
/// competing items rather than as a bar.
class SheetHeader extends StatelessWidget {
  const SheetHeader({this.title, this.leading, this.trailing, super.key});

  final String? title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (title != null)
            Text(
              title!,
              style: theme.textTheme.titleMedium,
            ),
          Positioned(
            left: 4,
            child: leading ?? const SizedBox.shrink(),
          ),
          Positioned(
            right: 4,
            child: trailing ?? const SizedBox.shrink(),
          ),
        ],
      ),
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
    backgroundColor:
        transparent ? Colors.transparent : Theme.of(context).colorScheme.surface,
    // Every sheet draws its own grabber, at iOS proportions.
    showDragHandle: false,
    builder: builder,
  );
}
