import 'package:flutter/material.dart';

/// Add this card to the existing Templates page. The host owns navigation and
/// connects [onOpen] to SmartPagesGalleryScreen.
class SmartPagesEntryCard extends StatelessWidget {
  const SmartPagesEntryCard({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.primaryContainer, colors.surfaceContainerHighest],
            ),
          ),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.auto_awesome, size: 28, color: colors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Smart Pages', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Ready-made planners, study sheets and more',
                  style: Theme.of(context).textTheme.bodySmall),
              ],
            )),
            const Icon(Icons.arrow_forward_ios, size: 16),
          ]),
        ),
      ),
    );
  }
}
