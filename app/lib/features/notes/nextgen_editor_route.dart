import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/local/note_repository.dart';
import 'editor_v2/editor_v2_page.dart';

/// Beta 79's isolated editor entry point.
///
/// The old NoteEditorPage/SnoteCanvas pipeline is deliberately not mounted
/// here. This route gives the independently implemented EditorV2 engine a
/// bounded, full-screen viewport and records the constraints at route entry.
class SnoteNextEditorRoute extends StatefulWidget {
  final LocalNote note;
  final Uint8List? initialPdfBytes;
  final String? initialPdfName;

  const SnoteNextEditorRoute({
    super.key,
    required this.note,
    this.initialPdfBytes,
    this.initialPdfName,
  });

  @override
  State<SnoteNextEditorRoute> createState() => _SnoteNextEditorRouteState();
}

class _SnoteNextEditorRouteState extends State<SnoteNextEditorRoute> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        debugPrint(
          '[Snote][Beta79Route] note=${widget.note.id} '
          'viewport=${constraints.maxWidth}x${constraints.maxHeight} '
          'pdfBytes=${widget.initialPdfBytes?.length ?? 0}',
        );

        if (!constraints.hasBoundedWidth ||
            !constraints.hasBoundedHeight ||
            constraints.maxWidth <= 0 ||
            constraints.maxHeight <= 0) {
          return Scaffold(
            appBar: AppBar(
              leading: const BackButton(),
              title: const Text('Editor unavailable'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.aspect_ratio_rounded,
                      size: 44,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Snote could not obtain a usable editor viewport.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Return to your notebook and reopen this note. '
                      'Your saved content has not been deleted.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return KeyedSubtree(
          key: ValueKey<String>('beta79-editor-${widget.note.id}'),
          child: EditorV2Page(
            key: ValueKey<String>('beta79-editor-engine-${widget.note.id}'),
            note: widget.note,
            initialPdfBytes: widget.initialPdfBytes,
            initialPdfName: widget.initialPdfName,
          ),
        );
      },
    );
  }
}
