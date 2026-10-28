import 'package:flutter/material.dart';

/// Compact floating toolbar surface shared by docked and free-position modes.
/// Tool/action creation stays in the editor so every existing feature remains wired.
class SnoteFloatingToolbar extends StatelessWidget {
  const SnoteFloatingToolbar({
    super.key,
    required this.children,
    required this.vertical,
    required this.compact,
    required this.fullScreen,
    required this.width,
    required this.marginLeft,
    required this.marginTop,
    required this.marginRight,
    required this.marginBottom,
    required this.paddingLeft,
    required this.paddingTop,
    required this.paddingRight,
    required this.paddingBottom,
  });

  final List<Widget> children;
  final bool vertical;
  final bool compact;
  final bool fullScreen;
  final double width;
  final double marginLeft;
  final double marginTop;
  final double marginRight;
  final double marginBottom;
  final double paddingLeft;
  final double paddingTop;
  final double paddingRight;
  final double paddingBottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tight = compact || fullScreen;
    return Container(
      margin: tight
          ? EdgeInsets.zero
          : EdgeInsets.fromLTRB(marginLeft, marginTop, marginRight, marginBottom),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: compact ? .88 : .96),
        borderRadius: BorderRadius.circular(compact ? 9 : 13),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .72),
          width: .7,
        ),
        boxShadow: compact || fullScreen
            ? const <BoxShadow>[]
            : <BoxShadow>[
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: .12),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(compact ? 9 : 13),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            padding: tight
                ? EdgeInsets.zero
                : EdgeInsets.fromLTRB(paddingLeft, paddingTop, paddingRight, paddingBottom),
            scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
            child: vertical
                ? Column(mainAxisSize: MainAxisSize.min, children: children)
                : Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }
}
