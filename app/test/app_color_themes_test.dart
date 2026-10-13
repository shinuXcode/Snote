import 'package:flutter_test/flutter_test.dart';

import '../lib/app/theme_controller.dart';

void main() {
  test('Snote exposes ten named color palettes plus the interface profile', () {
    final palettes = SnoteColorTheme.values
        .where((theme) => !theme.followsInterfaceProfile)
        .toList();

    expect(palettes, hasLength(10));
    expect(palettes.map((theme) => theme.name).toSet(), hasLength(10));
    expect(palettes.map((theme) => theme.color.toARGB32()).toSet(), hasLength(10));
    expect(palettes.every((theme) => theme.label.trim().isNotEmpty), isTrue);
  });

  test('profile option remains available for platform accent colors', () {
    expect(SnoteColorTheme.profile.followsInterfaceProfile, isTrue);
  });
}
