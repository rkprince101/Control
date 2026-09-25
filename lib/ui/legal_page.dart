import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/legal.dart';
import 'control_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// The privacy policy or the terms of use, as a page to read: the short
/// version first, then a card per section.
class LegalPage extends StatelessWidget {
  const LegalPage({required this.document, super.key});

  final LegalDocument document;

  static Route<void> route(LegalDocument document) =>
      MaterialPageRoute<void>(builder: (_) => LegalPage(document: document));

  static Future<void> open(BuildContext context, LegalDocument document) =>
      Navigator.of(context).push(route(document));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ControlColors.of(context);
    final isPolicy = identical(document, privacyPolicy);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // A comfortable line length on a wide screen.
          final side = math.max(20.0, (constraints.maxWidth - 720) / 2);
          return CustomScrollView(
            slivers: [
              SliverAppBar.large(
                title: Text(document.title),
                backgroundColor: scheme.surface,
                surfaceTintColor: Colors.transparent,
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(side, 0, side, 40),
                sliver: SliverList.list(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 16),
                      child: Text(
                        'Last updated ${document.updated}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                    HeroCard(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: scheme.surface.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              isPolicy
                                  ? Icons.privacy_tip_outlined
                                  : Icons.handshake_outlined,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'The short version',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  document.summary,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final section in document.sections) ...[
                      const SizedBox(height: 12),
                      _SectionCard(section: section),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Control is open source under the MIT licence.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  final LegalSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ControlColors.of(context);
    final body = theme.textTheme.bodyMedium?.copyWith(height: 1.5);

    return ControlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(section.heading, style: theme.textTheme.titleMedium),
          ),
          for (final paragraph in section.paragraphs) ...[
            const SizedBox(height: 8),
            Text(paragraph, style: body?.copyWith(color: colors.textMuted)),
          ],
          for (final (lead, text) in section.points) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 7, right: 12),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$lead. ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: text,
                          style: TextStyle(color: colors.textMuted),
                        ),
                      ],
                    ),
                    style: body,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
