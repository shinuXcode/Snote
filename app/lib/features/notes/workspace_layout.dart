import 'package:flutter/foundation.dart';

/// Whether the notebook should embed an editor beside the note list.
///
/// Touch devices always open notes in a full-screen route, even in landscape
/// or on large tablets. This prevents nested Scaffolds and split-view
/// constraints from hiding the editor header, canvas tools, or page surface.
bool usesSplitNoteWorkspace({
  required TargetPlatform platform,
  required double width,
}) {
  final touchPlatform =
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  return !touchPlatform && width >= 1120;
}
