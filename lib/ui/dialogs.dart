import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// What a dialog is about to do, which colours its badge and its button.
enum DialogTone {
  /// Nothing lost either way: setting a PIN, entering a password.
  neutral,

  /// Hard to take back, but not destructive: a timed lock, hard mode.
  caution,

  /// Something is deleted or spent for good.
  danger,
}

class _ToneColors {
  const _ToneColors(this.badge, this.onBadge, this.button, this.onButton);

  factory _ToneColors.of(BuildContext context, DialogTone tone) {
    final scheme = Theme.of(context).colorScheme;
    return switch (tone) {
      DialogTone.neutral => _ToneColors(
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        scheme.primary,
        scheme.onPrimary,
      ),
      DialogTone.caution => _ToneColors(
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        scheme.tertiary,
        scheme.onTertiary,
      ),
      DialogTone.danger => _ToneColors(
        scheme.errorContainer,
        scheme.onErrorContainer,
        scheme.error,
        scheme.onError,
      ),
    };
  }

  final Color badge;
  final Color onBadge;
  final Color button;
  final Color onButton;
}

/// Opens a dialog the app's way: the page behind dims and softens, and the
/// dialog grows into place rather than blinking on.
Future<T?> showControlDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final still = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.38),
    transitionDuration: still
        ? Duration.zero
        : const Duration(milliseconds: 320),
    pageBuilder: (context, _, _) => Builder(builder: builder),
    transitionBuilder: (context, animation, _, child) {
      final grow = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      final fade = CurvedAnimation(
        parent: animation,
        curve: const Interval(0, 0.6, curve: Curves.easeOut),
      );
      return AnimatedBuilder(
        animation: animation,
        builder: (context, child) => BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 5 * animation.value,
            sigmaY: 5 * animation.value,
          ),
          child: child,
        ),
        child: FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: Tween(begin: 0.9, end: 1.0).animate(grow),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Asks before something is done, and resolves true only on the confirming
/// button.
Future<bool> confirmAction(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String confirmLabel,
  String? message,
  Widget? detail,
  String cancelLabel = 'Cancel',
  DialogTone tone = DialogTone.neutral,
}) async {
  final confirmed = await showControlDialog<bool>(
    context,
    builder: (context) => ControlDialog(
      icon: icon,
      tone: tone,
      title: title,
      message: message,
      content: detail,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      onConfirm: () => Navigator.pop(context, true),
    ),
  );
  return confirmed ?? false;
}

/// The one dialog layout in the app: a tonal badge, a centred title and
/// message, whatever the dialog needs below, and two full-width buttons.
///
/// Buttons sit side by side while their labels fit and stack, confirm on
/// top, once they would not: at large text or on a narrow screen.
class ControlDialog extends StatelessWidget {
  const ControlDialog({
    required this.icon,
    required this.title,
    required this.confirmLabel,
    required this.onConfirm,
    this.message,
    this.content,
    this.cancelLabel = 'Cancel',
    this.onCancel,
    this.tone = DialogTone.neutral,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;

  /// Fields, a note, a picture of what is at stake.
  final Widget? content;

  final String confirmLabel;

  /// Null disables the button.
  final VoidCallback? onConfirm;

  final String cancelLabel;

  /// Defaults to closing the dialog with no result.
  final VoidCallback? onCancel;
  final DialogTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ControlColors.of(context);
    final tones = _ToneColors.of(context, tone);

    return Dialog(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: _Badge(
                  icon: icon,
                  color: tones.badge,
                  onColor: tones.onBadge,
                ),
              ),
              const SizedBox(height: 18),
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 10),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textMuted,
                    height: 1.45,
                  ),
                ),
              ],
              if (content != null) ...[const SizedBox(height: 20), content!],
              const SizedBox(height: 24),
              _Buttons(
                cancelLabel: cancelLabel,
                onCancel: onCancel ?? () => Navigator.pop(context),
                confirmLabel: confirmLabel,
                onConfirm: onConfirm,
                tones: tones,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The icon at the head of a dialog, on a soft squircle that settles into
/// place a beat after the dialog does.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.color,
    required this.onColor,
  });

  final IconData icon;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.55),
            blurRadius: 0,
            spreadRadius: 6,
          ),
        ],
      ),
      child: Icon(icon, size: 32, color: onColor),
    );
    if (MediaQuery.disableAnimationsOf(context)) return badge;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 480),
      curve: Curves.elasticOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: badge,
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons({
    required this.cancelLabel,
    required this.onCancel,
    required this.confirmLabel,
    required this.onConfirm,
    required this.tones,
  });

  final String cancelLabel;
  final VoidCallback onCancel;
  final String confirmLabel;
  final VoidCallback? onConfirm;
  final _ToneColors tones;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const shape = StadiumBorder();
    const size = Size(0, 52);

    final cancel = FilledButton(
      onPressed: onCancel,
      style: FilledButton.styleFrom(
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurface,
        minimumSize: size,
        shape: shape,
      ),
      child: Text(cancelLabel, textAlign: TextAlign.center),
    );
    final confirm = FilledButton(
      onPressed: onConfirm,
      style: FilledButton.styleFrom(
        backgroundColor: tones.button,
        foregroundColor: tones.onButton,
        minimumSize: size,
        shape: shape,
      ),
      child: Text(confirmLabel, textAlign: TextAlign.center),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final longest = [
          cancelLabel,
          confirmLabel,
        ].fold(0, (most, label) => label.length > most ? label.length : most);
        // Roughly what a label needs at labelLarge, padding included.
        final needs = (longest * 8.5 + 48) * scale;
        if (needs * 2 + 12 > constraints.maxWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [confirm, const SizedBox(height: 10), cancel],
          );
        }
        return Row(
          children: [
            Expanded(child: cancel),
            const SizedBox(width: 12),
            Expanded(child: confirm),
          ],
        );
      },
    );
  }
}

/// A tinted line inside a dialog: what is at stake, or what went wrong.
class DialogNote extends StatelessWidget {
  const DialogNote({
    required this.icon,
    required this.text,
    this.tone = DialogTone.neutral,
    super.key,
  });

  final IconData icon;
  final String text;
  final DialogTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground) = switch (tone) {
      DialogTone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      DialogTone.caution => (
        scheme.tertiaryContainer.withValues(alpha: 0.7),
        scheme.onTertiaryContainer,
      ),
      DialogTone.danger => (
        scheme.errorContainer.withValues(alpha: 0.7),
        scheme.onErrorContainer,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A password or PIN field that hides what is typed, with a toggle to check
/// it.
class SecretField extends StatefulWidget {
  const SecretField({
    required this.controller,
    required this.label,
    this.icon = Icons.key_rounded,
    this.autofocus = false,
    this.digitsOnly = false,
    this.maxLength,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool autofocus;

  /// A number pad, and nothing but digits.
  final bool digitsOnly;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<SecretField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: widget.controller,
      autofocus: widget.autofocus,
      obscureText: _hidden,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: widget.digitsOnly
          ? TextInputType.number
          : TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      inputFormatters: [
        if (widget.digitsOnly) FilteringTextInputFormatter.digitsOnly,
        if (widget.maxLength != null)
          LengthLimitingTextInputFormatter(widget.maxLength),
      ],
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: widget.digitsOnly && _hidden
          ? const TextStyle(letterSpacing: 6)
          : null,
      decoration: InputDecoration(
        labelText: widget.label,
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        prefixIcon: Icon(widget.icon),
        suffixIcon: IconButton(
          tooltip: _hidden ? 'Show' : 'Hide',
          onPressed: () => setState(() => _hidden = !_hidden),
          icon: Icon(
            _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}

/// A new secret typed twice, or an existing one typed once, checked before
/// the dialog closes. Shared by block passwords and the page PIN.
class SecretDialog extends StatefulWidget {
  const SecretDialog({
    required this.icon,
    required this.title,
    required this.action,
    required this.fieldLabel,
    required this.validate,
    this.message,
    this.repeatLabel,
    this.digitsOnly = false,
    this.maxLength,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String action;
  final String fieldLabel;

  /// Set when the secret is new: it is asked for twice.
  final String? repeatLabel;
  final bool digitsOnly;
  final int? maxLength;

  /// The problem with a typed secret, or null when it will do.
  final String? Function(String secret) validate;

  @override
  State<SecretDialog> createState() => _SecretDialogState();
}

class _SecretDialogState extends State<SecretDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    final secret = _first.text;
    final problem = widget.validate(secret);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (widget.repeatLabel != null && secret != _second.text) {
      setState(() => _error = 'The two entries do not match.');
      return;
    }
    Navigator.pop(context, secret);
  }

  void _clearError(String _) {
    if (_error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final repeat = widget.repeatLabel;
    return ControlDialog(
      icon: widget.icon,
      title: widget.title,
      message: widget.message,
      confirmLabel: widget.action,
      onConfirm: _submit,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SecretField(
            controller: _first,
            label: widget.fieldLabel,
            icon: widget.digitsOnly ? Icons.pin_outlined : Icons.key_rounded,
            autofocus: true,
            digitsOnly: widget.digitsOnly,
            maxLength: widget.maxLength,
            textInputAction: repeat == null
                ? TextInputAction.done
                : TextInputAction.next,
            onChanged: _clearError,
            onSubmitted: (_) => repeat == null ? _submit() : null,
          ),
          if (repeat != null) ...[
            const SizedBox(height: 12),
            SecretField(
              controller: _second,
              label: repeat,
              icon: Icons.replay_rounded,
              digitsOnly: widget.digitsOnly,
              maxLength: widget.maxLength,
              textInputAction: TextInputAction.done,
              onChanged: _clearError,
              onSubmitted: (_) => _submit(),
            ),
          ],
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _error == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: DialogNote(
                      icon: Icons.error_outline_rounded,
                      text: _error!,
                      tone: DialogTone.danger,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
