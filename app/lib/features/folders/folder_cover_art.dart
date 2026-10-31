import 'dart:math' as math;

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
    return (value ?? coverKey.hashCode).abs() % 400;
  }

  Widget _generated(BuildContext context) {
    final seed = _seed;
    if (seed >= 200) return _generatedAlternate(context, seed);
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
      4 => const <IconData>[
        Icons.workspace_premium_rounded, Icons.bubble_chart_rounded,
        Icons.architecture_rounded, Icons.waves_rounded,
        Icons.auto_awesome_rounded,
      ],
      5 => const <IconData>[
        Icons.rocket_launch_rounded, Icons.public_rounded,
        Icons.satellite_alt_rounded, Icons.auto_awesome_rounded,
      ],
      6 => const <IconData>[
        Icons.change_history_rounded, Icons.hexagon_rounded,
        Icons.diamond_rounded, Icons.grid_4x4_rounded,
      ],
      7 => const <IconData>[
        Icons.memory_rounded, Icons.devices_rounded,
        Icons.code_rounded, Icons.developer_board_rounded,
      ],
      8 => const <IconData>[
        Icons.history_edu_rounded, Icons.menu_book_rounded,
        Icons.translate_rounded, Icons.edit_note_rounded,
      ],
      _ => const <IconData>[
        Icons.circle_outlined, Icons.blur_on_rounded,
        Icons.dashboard_customize_rounded, Icons.interests_rounded,
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
                'SNOTEE  •  ' + (seed + 1).toString().padLeft(3, '0'),
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

  Widget _generatedAlternate(BuildContext context, int seed) {
    final local = seed - 200;
    final hue = (local * 67.0 + 19) % 360;
    final base = HSVColor.fromAHSV(1, hue, .62, .88).toColor();
    final deep = HSVColor.fromAHSV(1, (hue + 44) % 360, .72, .32).toColor();
    final accent = HSVColor.fromAHSV(1, (hue + 175) % 360, .35, 1).toColor();
    final symbols = switch (local ~/ 40) {
      0 => const <IconData>[Icons.rocket_launch_rounded, Icons.public_rounded, Icons.satellite_alt_rounded],
      1 => const <IconData>[Icons.hexagon_rounded, Icons.change_history_rounded, Icons.diamond_rounded],
      2 => const <IconData>[Icons.memory_rounded, Icons.devices_rounded, Icons.code_rounded],
      3 => const <IconData>[Icons.history_edu_rounded, Icons.menu_book_rounded, Icons.translate_rounded],
      _ => const <IconData>[Icons.circle_outlined, Icons.blur_on_rounded, Icons.grid_4x4_rounded],
    };
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: local.isEven ? Alignment.topCenter : Alignment.centerLeft,
          end: local.isEven ? Alignment.bottomCenter : Alignment.centerRight,
          colors: [base, deep],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _CoverPatternPainter(
              seed: local,
              accent: accent.withValues(alpha: .38),
            ),
          ),
          Positioned(
            right: 15,
            top: 24,
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .12),
                border: Border.all(color: Colors.white.withValues(alpha: .25)),
              ),
              child: Icon(
                symbols[local % symbols.length],
                size: 34,
                color: Colors.white.withValues(alpha: .92),
              ),
            ),
          ),
          if (showBrandLabel)
            Positioned(
              left: 12,
              top: 12,
              child: Text(
                'SNOTEE  •  ${(seed + 1).toString().padLeft(3, '0')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 22,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
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

class _CoverPatternPainter extends CustomPainter {
  final int seed;
  final Color accent;

  const _CoverPatternPainter({required this.seed, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    switch (seed % 5) {
      case 0:
        for (var x = -size.height; x < size.width; x += 18) {
          canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
        }
        break;
      case 1:
        final center = Offset(size.width * .35, size.height * .55);
        for (var radius = 24.0; radius < size.width * 1.4; radius += 16) {
          canvas.drawCircle(center, radius, paint);
        }
        break;
      case 2:
        for (var y = 14.0; y < size.height; y += 22) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y + 10), paint);
        }
        break;
      case 3:
        final path = Path();
        for (var x = 0.0; x <= size.width; x += 16) {
          final y = size.height * .5 + math.sin((x / size.width * math.pi * 4) + seed) * 24;
          if (x == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(path, paint);
        break;
      default:
        for (var x = 16.0; x < size.width; x += 28) {
          for (var y = 16.0; y < size.height; y += 28) {
            canvas.drawCircle(Offset(x, y), 4 + ((x + y).toInt() % 5), paint);
          }
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _CoverPatternPainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.accent != accent;
}

