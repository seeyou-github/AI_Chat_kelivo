import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider startup bootstrap', () {
    test('bootstrap fields are ready before deferred load completes', () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode_v1': 'dark',
        'selected_model_v1': 'OpenAI::gpt-4.1',
        'display_new_chat_on_launch_v1': false,
        'display_desktop_show_tray_v1': true,
        'display_desktop_minimize_to_tray_on_close_v1': true,
        'display_app_font_family_v1': 'Segoe UI',
        'display_code_font_family_v1': 'Consolas',
        'app_locale_v1': 'en_US',
        'search_auto_test_on_launch_v1': true,
        'global_proxy_enabled_v1': true,
        'global_proxy_type_v1': 'http',
        'global_proxy_host_v1': '127.0.0.1',
        'global_proxy_port_v1': '7890',
        'webdav_config_v1': jsonEncode({
          'url': 'https://dav.example.com',
          'username': 'tester',
          'password': 'secret',
          'path': 'kelivo_backups',
          'includeChats': true,
          'includeFiles': false,
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      final settings = SettingsProvider(initialPrefs: prefs);

      expect(settings.deferredLoadCompleted, isFalse);
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.currentModelProvider, 'OpenAI');
      expect(settings.currentModelId, 'gpt-4.1');
      expect(settings.newChatOnLaunch, isFalse);
      expect(settings.desktopShowTray, isTrue);
      expect(settings.desktopMinimizeToTrayOnClose, isTrue);
      expect(settings.appFontFamily, 'Segoe UI');
      expect(settings.codeFontFamily, 'Consolas');
      expect(settings.appLocaleForMaterialApp, const Locale('en', 'US'));
      expect(settings.globalProxyEnabled, isTrue);
      expect(settings.globalProxyHost, '127.0.0.1');
      expect(settings.webDavConfig.url, 'https://dav.example.com');
      expect(settings.searchAutoTestOnLaunch, isFalse);

      await settings.ensureDeferredLoaded(initialPrefs: prefs);

      expect(settings.deferredLoadCompleted, isTrue);
      expect(settings.searchAutoTestOnLaunch, isTrue);
    });
  });
}
