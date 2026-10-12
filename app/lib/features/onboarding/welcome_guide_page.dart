import 'package:flutter/material.dart';

class WelcomeGuidePage extends StatefulWidget {
  const WelcomeGuidePage({super.key});

  @override
  State<WelcomeGuidePage> createState() => _WelcomeGuidePageState();
}

class _WelcomeGuidePageState extends State<WelcomeGuidePage> {
  final PageController _pages = PageController();
  int _index = 0;

  static const _guides = <_GuideStep>[
    _GuideStep(
      icon: Icons.create_new_folder_rounded,
      title: 'Organize folders and covers',
      body: 'Create nested folders and choose built-in or custom covers. Long-press a folder to select it; the three-dot menu contains move, copy, cut, details, rename and delete.',
      tip: 'Custom cover images are saved locally on this device.',
    ),
    _GuideStep(
      icon: Icons.draw_rounded,
      title: 'Write naturally',
      body: 'Choose a pen and double-tap a tool for its settings. Drag the toolbox grip to float it or snap it to an edge. Add favorite color and size variants to the separate Tool Showcase.',
      tip: 'Use a stylus for precise writing and keep palm rejection enabled when appropriate.',
    ),
    _GuideStep(
      icon: Icons.picture_as_pdf_rounded,
      title: 'Use PDFs and screenshots',
      body: 'Import PDFs for annotation, export pages, or add images to your note. On Android, use the system screenshot preview Share action to send an image into Snote.',
      tip: 'Snote does not silently capture other apps; system screenshots require your action.',
    ),
    _GuideStep(
      icon: Icons.style_rounded,
      title: 'Study with flashcards and mind maps',
      body: 'Create front/back flashcards and review cards one by one. Build a mind map by selecting a parent idea, adding child branches, moving nodes, changing the canvas background and arranging the tree.',
      tip: 'Save your cards and maps into the notebook so they stay with your notes.',
    ),
    _GuideStep(
      icon: Icons.lock_outline_rounded,
      title: 'Keep control of your notes',
      body: 'Snote is offline-first. Private transfer is intended for local QR handoff. Your notes remain on this device unless you enable optional synchronization or export them.',
      tip: 'Make a backup before resetting your device or moving notes to another device.',
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to Snote'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Skip guide')),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
              child: Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: _guides.length,
                      onPageChanged: (value) => setState(() => _index = value),
                      itemBuilder: (context, index) {
                        final step = _guides[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          child: Card(
                            elevation: 3,
                            shadowColor: theme.colorScheme.shadow.withValues(alpha: .12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                              side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: .55)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(26),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 76,
                                    height: 76,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Icon(step.icon, size: 38, color: theme.colorScheme.onPrimaryContainer),
                                  ),
                                  const SizedBox(height: 26),
                                  Text(step.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 14),
                                  Text(step.body, style: theme.textTheme.bodyLarge?.copyWith(height: 1.55)),
                                  const SizedBox(height: 18),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(step.tip, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _guides.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          height: 8,
                          width: i == _index ? 24 : 8,
                          decoration: BoxDecoration(
                            color: i == _index ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _index == 0 ? null : () => _pages.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
                        icon: const Icon(Icons.chevron_left_rounded),
                        label: const Text('Back'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: () {
                          if (_index == _guides.length - 1) {
                            Navigator.pop(context);
                          } else {
                            _pages.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
                          }
                        },
                        icon: Icon(_index == _guides.length - 1 ? Icons.check_rounded : Icons.chevron_right_rounded),
                        label: Text(_index == _guides.length - 1 ? 'Start using Snote' : 'Next'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideStep {
  final IconData icon;
  final String title;
  final String body;
  final String tip;

  const _GuideStep({
    required this.icon,
    required this.title,
    required this.body,
    required this.tip,
  });
}
