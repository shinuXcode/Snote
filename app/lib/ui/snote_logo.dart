import 'package:flutter/widgets.dart';

class SnoteLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;

  const SnoteLogo({
    super.key,
    this.size = 42,
    this.showWordmark = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/branding/snote-logo.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          isAntiAlias: true,
          semanticLabel: 'Snotee',
        ),
        if (showWordmark) ...[
          const SizedBox(width: 10),
          const Text(
            'Snotee',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
        ],
      ],
    );
  }
}
