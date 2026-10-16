import 'package:flutter/material.dart';

import 'folder_cover_repository.dart';

class FolderCoverArt extends StatelessWidget {
  final String coverKey;
  final String? title;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final bool showTitle;
  final bool showBrandLabel;

  const FolderCoverArt({
    super.key,
    required this.coverKey,
    this.title,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.showTitle = true,
    this.showBrandLabel = true,
  });

  int get _seed {
    if (!coverKey.startsWith('cover:')) return 0;
    final value = int.tryParse(coverKey.substring('cover:'.length));
    return (value ?? coverKey.hashCode).abs() % 200;
  }

  Widget _generated(BuildContext context) {
    final seed = _seed;
    final hue = (seed * 47.0) % 360;
    final top = HSVColor.fromAHSV(1, hue, .43 + (seed % 3) * .12, .97).toColor();
    final bottom = HSVColor.fromAHSV(1, (hue + 35) % 360, .78, .46 + (seed % 4) * .1).toColor();
    // The cover library is organized into five visible collections of forty.
    // Each collection deliberately uses related symbols so users can browse by
    // subject rather than relying on color alone.
    final symbols = switch (seed ~/ 40) {
      0 => const <IconData>[
        Icons.menu_book_rounded, Icons.auto_stories_rounded,
        Icons.functions_rounded, Icons.calculate_rounded,
      ],
      1 => const <IconData>[
        Icons.science_rounded, Icons.biotech_rounded,
        Icons.bubble_chart_rounded, Icons.architecture_rounded,
      ],
      2 => const <IconData>[
        Icons.eco_rounded, Icons.public_rounded,
        Icons.terrain_rounded, Icons.waves_rounded,
        Icons.nights_stay_rounded,
      ],
      3 => const <IconData>[
        Icons.palette_rounded, Icons.music_note_rounded,
        Icons.star_rounded, Icons.lightbulb_rounded,
      ],
      _ => const <IconData>[
        Icons.workspace_premium_rounded, Icons.bubble_chart_rounded,
        Icons.architecture_rounded, Icons.waves_rounded,
        Icons.auto_awesome_rounded,
      ],
    };
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: seed.isEven ? Alignment.topLeft : Alignment.topRight,
          end: seed.isEven ? Alignment.bottomRight : Alignment.bottomLeft,
          colors: [top, bottom],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(top: -24, right: -22, child: CircleAvatar(
            radius: 62 + (seed % 4) * 8,
            backgroundColor: Colors.white.withValues(alpha: .12),
          )),
          Positioned(left: -30, bottom: -18, child: CircleAvatar(
            radius: 56,
            backgroundColor: Colors.black.withValues(alpha: .09),
          )),
          Positioned(right: 12, top: 17, child: Icon(
            symbols[seed % symbols.length], size: 52,
            color: Colors.white.withValues(alpha: .85),
          )),
          if (showBrandLabel)
            Positioned(left: 12, top: 12, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                'SNOTE  •  ' + (seed + 1).toString().padLeft(3, '0'),
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            )),
          Positioned(left: 17, bottom: 23, child: Icon(
            symbols[(seed * 7 + 3) % symbols.length],
            size: 58, color: Colors.white.withValues(alpha: .22),
          )),
          Positioned(left: 14, right: 14, bottom: 9, child: Container(
            height: 1, color: Colors.white.withValues(alpha: .25),
          )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget art = _generated(context);
    if (coverKey.startsWith('cover:custom-')) {
      art = FutureBuilder(
        future: FolderCoverRepository.instance.imageForKey(coverKey),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) return _generated(context);
          return Image.memory(
            bytes, fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _generated(context),
          );
        },
      );
    }
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            art,
            if (showTitle)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: .8)],
                    ),
                  ),
                  child: Text(
                    title ?? ('Cover ' + (_seed + 1).toString().padLeft(3, '0')),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800, height: 1.15),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
