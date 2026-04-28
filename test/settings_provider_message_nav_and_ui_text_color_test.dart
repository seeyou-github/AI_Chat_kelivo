import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';

Future<void> _waitForSettingsLoad() async {
  for (var i = 0; i < 25; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider message navigation and UI text color', () {
    test(
      'defaults to scrolling-only navigation and theme UI text color',
      () async {
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsProvider();

        await _waitForSettingsLoad();

        expect(settings.alwaysShowMessageNavButtons, isFalse);
        expect(settings.customUiTextColor(Brightness.light), isNull);
        expect(settings.customUiTextColor(Brightness.dark), isNull);
      },
    );

    test('loads persisted values', () async {
      SharedPreferences.setMockInitialValues({
        'display_always_show_message_nav_v1': true,
        'display_ui_text_light_color_v1': 0xFF2468AC,
        'display_ui_text_dark_color_v1': 0xFFECA864,
      });
      final settings = SettingsProvider();

      await _waitForSettingsLoad();

      expect(settings.alwaysShowMessageNavButtons, isTrue);
      expect(
        settings.customUiTextColor(Brightness.light),
        const Color(0xFF2468AC),
      );
      expect(
        settings.customUiTextColor(Brightness.dark),
        const Color(0xFFECA864),
      );
    });

    test('persists toggles and resets UI text colors', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();

      await _waitForSettingsLoad();
      await settings.setAlwaysShowMessageNavButtons(true);
      await settings.setUiTextLightColor(const Color(0xFF13579B));
      await settings.setUiTextDarkColor(const Color(0xFFB97531));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('display_always_show_message_nav_v1'), isTrue);
      expect(prefs.getInt('display_ui_text_light_color_v1'), 0xFF13579B);
      expect(prefs.getInt('display_ui_text_dark_color_v1'), 0xFFB97531);

      await settings.resetUiTextColor(Brightness.light);
      await settings.resetUiTextColor(Brightness.dark);

      expect(settings.customUiTextColor(Brightness.light), isNull);
      expect(settings.customUiTextColor(Brightness.dark), isNull);
      expect(prefs.containsKey('display_ui_text_light_color_v1'), isFalse);
      expect(prefs.containsKey('display_ui_text_dark_color_v1'), isFalse);
    });
  });
}
