import 'package:Kelivo/desktop/window_size_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('WindowSizeManager', () {
    test('uses the saved startup size', () async {
      SharedPreferences.setMockInitialValues({
        'window_width_v1': 1440.0,
        'window_height_v1': 900.0,
      });

      final size = await const WindowSizeManager().getInitialSize();

      expect(size, const Size(1440, 900));
    });

    test('clamps saved startup size to supported bounds', () async {
      SharedPreferences.setMockInitialValues({
        'window_width_v1': 320.0,
        'window_height_v1': 200.0,
      });

      final size = await const WindowSizeManager().getInitialSize();

      expect(
        size,
        const Size(
          WindowSizeManager.minWindowWidth,
          WindowSizeManager.minWindowHeight,
        ),
      );
    });

    test('centers the startup window inside the work area', () {
      final position = WindowSizeManager.centerPositionForWorkArea(
        workArea: const Rect.fromLTWH(100, 50, 1400, 900),
        windowSize: const Size(1000, 600),
      );

      expect(position, const Offset(300, 200));
    });
  });
}
