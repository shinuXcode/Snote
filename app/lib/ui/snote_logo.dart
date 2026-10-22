import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
        SvgPicture.asset(
          'assets/branding/snotee-mark.svg',
          width: size,
          height: size,
          semanticsLabel: 'Snotee',
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
