import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/feed_item.dart';

/// Tarjeta del feed proactivo con acento por prioridad y feedback rápido.
class ProactiveCard extends StatelessWidget {
  const ProactiveCard({
    super.key,
    required this.item,
    required this.onDismiss,
    this.onFeedback,
    this.onTap,
  });

  final FeedItem item;
  final VoidCallback onDismiss;
  final void Function(String value)? onFeedback;
  final VoidCallback? onTap;

  Color get _accent => switch (item.priority) {
        'critical' => JColors.red,
        'high' => JColors.amber,
        'medium' => JColors.cyan,
        _ => JColors.muted,
      };

  IconData get _icon => switch (item.kind) {
        FeedKind.opportunity => Icons.trending_up_rounded,
        FeedKind.task => Icons.push_pin_outlined,
        FeedKind.summary => Icons.insights_rounded,
        FeedKind.answer => Icons.record_voice_over_outlined,
        FeedKind.info => Icons.lightbulb_outline_rounded,
        FeedKind.alert => Icons.warning_amber_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.done_all_rounded, color: JColors.textSecondary),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: _accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(_icon, size: 18, color: _accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.title,
                                style: theme.textTheme.titleMedium?.copyWith(fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(DateFormat('HH:mm').format(item.createdAt), style: theme.textTheme.bodySmall),
                          ],
                        ),
                        if (item.body.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(item.body, style: theme.textTheme.bodyMedium),
                        ],
                        if (onFeedback != null && item.refId != null && item.kind != FeedKind.summary)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _FeedbackButton(
                                  icon: Icons.thumb_up_alt_outlined,
                                  selected: item.feedback == 'useful',
                                  tooltip: 'Me sirvió',
                                  onTap: () => onFeedback!('useful'),
                                ),
                                _FeedbackButton(
                                  icon: Icons.thumb_down_alt_outlined,
                                  selected: item.feedback == 'not_useful',
                                  tooltip: 'No me sirvió',
                                  onTap: () => onFeedback!('not_useful'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackButton extends StatelessWidget {
  const _FeedbackButton({required this.icon, required this.selected, required this.tooltip, required this.onTap});

  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: tooltip,
        iconSize: 18,
        color: selected ? JColors.cyan : JColors.textSecondary,
        onPressed: onTap,
        icon: Icon(icon),
      );
}
