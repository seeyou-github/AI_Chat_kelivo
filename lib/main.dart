import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'dart:async';
import 'l10n/app_localizations.dart';
import 'features/home/pages/home_page.dart';
import 'desktop/desktop_home_page.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'desktop/desktop_window_controller.dart';
import 'desktop/desktop_tray_controller.dart';
// import 'package:logging/logging.dart' as logging;
// Theme is now managed in SettingsProvider
import 'theme/theme_factory.dart';
import 'theme/palettes.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'core/providers/chat_provider.dart';
import 'core/providers/user_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/mcp_provider.dart';
import 'core/providers/tts_provider.dart';
import 'core/providers/assistant_provider.dart';
import 'core/providers/tag_provider.dart';
import 'core/providers/update_provider.dart';
import 'core/providers/quick_phrase_provider.dart';
import 'core/providers/instruction_injection_provider.dart';
import 'core/providers/instruction_injection_group_provider.dart';
import 'core/providers/world_book_provider.dart';
import 'core/providers/memory_provider.dart';
import 'core/providers/backup_provider.dart';
import 'core/providers/s3_backup_provider.dart';
import 'core/providers/hotkey_provider.dart';
import 'core/services/chat/chat_service.dart';
import 'core/services/mcp/mcp_tool_service.dart';
import 'core/services/logging/flutter_logger.dart';
import 'features/home/services/tool_approval_service.dart';
import 'utils/sandbox_path_resolver.dart';
import 'shared/widgets/snackbar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:system_fonts/system_fonts.dart';
import 'dart:io'
    show Platform; // kept for global override usage inside provider
import 'core/services/android_background.dart';
import 'core/services/notification_service.dart';
import 'core/services/storage/windows_portable_storage.dart';
import 'core/services/storage/windows_portable_path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final RouteObserver<ModalRoute<dynamic>> routeObserver =
    RouteObserver<ModalRoute<dynamic>>();
bool _didCheckUpdates = false; // one-time update check flag
bool _didEnsureAssistants = false; // ensure defaults after l10n ready
SharedPreferences? _bootstrapPrefs;
bool _didScheduleDeferredStartupTasks = false;
bool _didWarmSystemFonts = false;
bool _didInitDesktopHotkeys = false;
bool _didInitAndroidBackground = false;
bool? _lastDynamicColorSupported;
String? _lastTraySyncSignature;

Future<void> main() async {
  await runZoned(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await WindowsPortableStorage.installIfNeeded();
      await WindowsPortablePathProvider.installIfNeeded();
      FlutterLogger.installGlobalHandlers();
      try {
        _bootstrapPrefs = await SharedPreferences.getInstance();
        final enabled =
            _bootstrapPrefs!.getBool('flutter_log_enabled_v1') ?? false;
        await FlutterLogger.setEnabled(enabled);
      } catch (_) {}
      // Trim Flutter global image cache to reduce memory pressure from large images
      try {
        PaintingBinding.instance.imageCache.maximumSize = 200;
        PaintingBinding.instance.imageCache.maximumSizeBytes =
            48 << 20; // ~48MB
      } catch (_) {}
      // Desktop (Windows) window setup: hide native title bar for custom Flutter bar
      await _initDesktopWindow(initialPrefs: _bootstrapPrefs);
      // Avoid preloading all system fonts at launch (huge memory on desktop)
      // Debug logging and global error handlers were enabled previously for diagnosis.
      // They are commented out now per request to reduce log noise.
      // FlutterError.onError = (FlutterErrorDetails details) { ... };
      // WidgetsBinding.instance.platformDispatcher.onError = (Object error, StackTrace stack) { ... };
      // logging.Logger.root.level = logging.Level.ALL;
      // logging.Logger.root.onRecord.listen((rec) { ... });
      // Cache current Documents directory to fix sandboxed absolute paths on iOS
      await SandboxPathResolver.init();
      // Enable edge-to-edge to allow content under system bars (Android)
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // Start app (Flutter log capture is toggleable and off by default)
      runApp(MyApp(initialPrefs: _bootstrapPrefs));
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        FlutterLogger.logPrint(line);
        parent.print(zone, line);
      },
    ),
  );
}

Future<void> _initDesktopWindow({SharedPreferences? initialPrefs}) async {
  if (kIsWeb) return;
  try {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await windowManager.ensureInitialized();
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }
    // Initialize and show desktop window with persisted size/position
    await DesktopWindowController.instance.initializeAndShow(
      title: 'Kelivo',
      initialPrefs: initialPrefs,
    );
  } catch (_) {
    // Ignore on unsupported platforms.
  }
}

bool _isDesktopPlatform() =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

void _updateDynamicColorSupportIfNeeded(
  SettingsProvider settings,
  bool dynSupported,
) {
  if (_lastDynamicColorSupported == dynSupported) return;
  _lastDynamicColorSupported = dynSupported;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      settings.setDynamicColorSupported(dynSupported);
    } catch (_) {}
  });
}

void _syncDesktopTrayIfNeeded(
  BuildContext context,
  AppLocalizations? l10n,
  SettingsProvider settings,
) {
  if (l10n == null || !_isDesktopPlatform()) return;
  final signature =
      '${l10n.localeName}|${settings.desktopShowTray}|${settings.desktopMinimizeToTrayOnClose}';
  if (_lastTraySyncSignature == signature) return;
  _lastTraySyncSignature = signature;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!context.mounted) return;
    try {
      await DesktopTrayController.instance.syncFromSettings(
        l10n,
        showTray: settings.desktopShowTray,
        minimizeToTrayOnClose: settings.desktopMinimizeToTrayOnClose,
      );
    } catch (_) {}
  });
}

void _scheduleDeferredStartupTasks(BuildContext context) {
  if (_didScheduleDeferredStartupTasks) return;
  _didScheduleDeferredStartupTasks = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_runDeferredStartupTasks(context));
  });
}

Future<void> _runDeferredStartupTasks(BuildContext context) async {
  if (!context.mounted) return;

  final l10n = AppLocalizations.of(context);
  await Future<void>.delayed(const Duration(milliseconds: 250));
  if (!context.mounted) return;
  final settings = context.read<SettingsProvider>();

  if (!_didEnsureAssistants && l10n != null) {
    _didEnsureAssistants = true;
    try {
      await context.read<AssistantProvider>().ensureDefaults(context);
    } catch (_) {}
    try {
      context.read<ChatService>().setDefaultConversationTitle(
        l10n.chatServiceDefaultConversationTitle,
      );
    } catch (_) {}
    try {
      context.read<UserProvider>().setDefaultNameIfUnset(
        l10n.userProviderDefaultUserName,
      );
    } catch (_) {}
  }

  if (_isDesktopPlatform() && !_didWarmSystemFonts) {
    _didWarmSystemFonts = true;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!context.mounted) return;
    try {
      final wantsAppSystem =
          (settings.appFontFamily?.isNotEmpty == true) &&
          !settings.appFontIsGoogle &&
          (settings.appFontLocalAlias == null ||
              settings.appFontLocalAlias!.isEmpty);
      final wantsCodeSystem =
          (settings.codeFontFamily?.isNotEmpty == true) &&
          !settings.codeFontIsGoogle &&
          (settings.codeFontLocalAlias == null ||
              settings.codeFontLocalAlias!.isEmpty);
      if (wantsAppSystem || wantsCodeSystem) {
        final sf = SystemFonts();
        if (wantsAppSystem) {
          final fam = settings.appFontFamily!;
          try {
            await sf.loadFont(fam);
          } catch (_) {}
        }
        if (wantsCodeSystem) {
          final fam = settings.codeFontFamily!;
          try {
            if (fam != settings.appFontFamily) await sf.loadFont(fam);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  if (_isDesktopPlatform() && !_didInitDesktopHotkeys) {
    _didInitDesktopHotkeys = true;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!context.mounted) return;
    try {
      await context.read<HotkeyProvider>().initialize();
    } catch (_) {}
  }

  if (!_didCheckUpdates && settings.showAppUpdates) {
    _didCheckUpdates = true;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!context.mounted) return;
    try {
      context.read<UpdateProvider>().checkForUpdates();
    } catch (_) {}
  }

  if (!_didInitAndroidBackground && Platform.isAndroid) {
    _didInitAndroidBackground = true;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!context.mounted) return;
    try {
      final mode = settings.androidBackgroundChatMode;
      if (mode != AndroidBackgroundChatMode.off && l10n != null) {
        try {
          final already = await AndroidBackgroundManager.isEnabled();
          if (!already) {
            await AndroidBackgroundManager.ensureInitialized(
              notificationTitle: l10n.androidBackgroundNotificationTitle,
              notificationText: l10n.androidBackgroundNotificationText,
            );
            await AndroidBackgroundManager.setEnabled(true);
          }
        } catch (_) {}
        if (mode == AndroidBackgroundChatMode.onNotify) {
          await NotificationService.ensureInitialized();
          await NotificationService.ensureAndroidNotificationsPermission();
        }
      }
    } catch (_) {}
  }

  try {
    context.read<McpProvider>().scheduleDeferredAutoConnect();
  } catch (_) {}
}

// Removed eager system font preloading to reduce memory footprint at launch.

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.initialPrefs});

  final SharedPreferences? initialPrefs;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(
          create: (_) => UserProvider(initialPrefs: initialPrefs),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(initialPrefs: initialPrefs),
        ),
        ChangeNotifierProvider(create: (_) => ChatService()),
        ChangeNotifierProvider(create: (_) => McpToolService()),
        ChangeNotifierProvider(
          create: (_) => McpProvider(initialPrefs: initialPrefs),
        ),
        ChangeNotifierProvider(create: (_) => ToolApprovalService()),
        ChangeNotifierProvider(
          create: (_) => AssistantProvider(initialPrefs: initialPrefs),
        ),
        ChangeNotifierProvider(create: (_) => TagProvider()),
        ChangeNotifierProvider(create: (_) => TtsProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
        ChangeNotifierProvider(create: (_) => QuickPhraseProvider()),
        ChangeNotifierProvider(create: (_) => InstructionInjectionProvider()),
        ChangeNotifierProvider(
          create: (_) => InstructionInjectionGroupProvider(),
        ),
        ChangeNotifierProvider(create: (_) => WorldBookProvider()),
        ChangeNotifierProvider(create: (_) => MemoryProvider()),
        // Desktop hotkeys provider
        ChangeNotifierProvider(create: (_) => HotkeyProvider()),
        ChangeNotifierProvider(
          create: (ctx) => BackupProvider(
            chatService: ctx.read<ChatService>(),
            initialConfig: ctx.read<SettingsProvider>().webDavConfig,
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) => S3BackupProvider(
            chatService: ctx.read<ChatService>(),
            initialConfig: ctx.read<SettingsProvider>().s3Config,
          ),
        ),
      ],
      child: Builder(
        builder: (context) {
          final settings = context.watch<SettingsProvider>();
          // Apply global proxy overrides when settings change
          settings.applyGlobalProxyOverridesIfNeeded();
          return DynamicColorBuilder(
            builder: (lightDynamic, darkDynamic) {
              // if (lightDynamic != null) {
              //   debugPrint('[DynamicColor] Light dynamic detected. primary=${lightDynamic.primary.value.toRadixString(16)} surface=${lightDynamic.surface.value.toRadixString(16)}');
              // } else {
              //   debugPrint('[DynamicColor] Light dynamic not available');
              // }
              // if (darkDynamic != null) {
              //   debugPrint('[DynamicColor] Dark dynamic detected. primary=${darkDynamic.primary.value.toRadixString(16)} surface=${darkDynamic.surface.value.toRadixString(16)}');
              // } else {
              //   debugPrint('[DynamicColor] Dark dynamic not available');
              // }
              final isAndroid =
                  Theme.of(context).platform == TargetPlatform.android;
              // Update dynamic color capability for settings UI (avoid notify during build)
              final dynSupported =
                  isAndroid && (lightDynamic != null || darkDynamic != null);
              _updateDynamicColorSupportIfNeeded(settings, dynSupported);

              final useDyn = isAndroid && settings.useDynamicColor;
              final palette = ThemePalettes.byId(settings.themePaletteId);

              final light = buildLightThemeForScheme(
                palette.light,
                dynamicScheme: useDyn ? lightDynamic : null,
                pureBackground: settings.usePureBackground,
              );
              final dark = buildDarkThemeForScheme(
                palette.dark,
                dynamicScheme: useDyn ? darkDynamic : null,
                pureBackground: settings.usePureBackground,
              );
              // Resolve effective app font family (system/Google/local alias)
              String? effectiveAppFontFamily() {
                final fam = settings.appFontFamily;
                if (fam == null || fam.isEmpty) return null;
                if (settings.appFontIsGoogle) {
                  try {
                    final s = GoogleFonts.getFont(fam);
                    return s.fontFamily ?? fam;
                  } catch (_) {
                    return fam;
                  }
                }
                return fam;
              }

              final effectiveAppFont = effectiveAppFontFamily();

              // Apply user-selected app font to theme text styles and app bar
              ThemeData applyAppFont(ThemeData base) {
                if (effectiveAppFont == null || effectiveAppFont.isEmpty) {
                  return base;
                }
                TextStyle? withFamily(TextStyle? s) =>
                    s?.copyWith(fontFamily: effectiveAppFont);
                TextTheme apply(TextTheme t) => t.copyWith(
                  displayLarge: withFamily(t.displayLarge),
                  displayMedium: withFamily(t.displayMedium),
                  displaySmall: withFamily(t.displaySmall),
                  headlineLarge: withFamily(t.headlineLarge),
                  headlineMedium: withFamily(t.headlineMedium),
                  headlineSmall: withFamily(t.headlineSmall),
                  titleLarge: withFamily(t.titleLarge),
                  titleMedium: withFamily(t.titleMedium),
                  titleSmall: withFamily(t.titleSmall),
                  bodyLarge: withFamily(t.bodyLarge),
                  bodyMedium: withFamily(t.bodyMedium),
                  bodySmall: withFamily(t.bodySmall),
                  labelLarge: withFamily(t.labelLarge),
                  labelMedium: withFamily(t.labelMedium),
                  labelSmall: withFamily(t.labelSmall),
                );
                final bar = base.appBarTheme;
                final appBar = bar.copyWith(
                  titleTextStyle: (bar.titleTextStyle ?? const TextStyle())
                      .copyWith(fontFamily: effectiveAppFont),
                  toolbarTextStyle: (bar.toolbarTextStyle ?? const TextStyle())
                      .copyWith(fontFamily: effectiveAppFont),
                );
                // Apply as default family to all text in ThemeData
                return base.copyWith(
                  textTheme: apply(base.textTheme),
                  primaryTextTheme: apply(base.primaryTextTheme),
                  appBarTheme: appBar,
                );
              }

              final themedLight = applyAppFont(light);
              final themedDark = applyAppFont(dark);
              // Log top-level colors likely used by widgets (card/bg/shadow approximations)
              // debugPrint('[Theme/App] Light scaffoldBg=${light.colorScheme.surface.value.toRadixString(16)} card≈${light.colorScheme.surface.value.toRadixString(16)} shadow=${light.colorScheme.shadow.value.toRadixString(16)}');
              // debugPrint('[Theme/App] Dark scaffoldBg=${dark.colorScheme.surface.value.toRadixString(16)} card≈${dark.colorScheme.surface.value.toRadixString(16)} shadow=${dark.colorScheme.shadow.value.toRadixString(16)}');
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                title: 'Kelivo',
                // App UI language; null = follow system (respects iOS per-app language)
                locale: settings.appLocaleForMaterialApp,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                theme: themedLight,
                darkTheme: themedDark,
                themeMode: settings.themeMode,
                navigatorObservers: <NavigatorObserver>[routeObserver],
                home: _selectHome(),
                builder: (ctx, child) {
                  _scheduleDeferredStartupTasks(ctx);
                  final bright = Theme.of(ctx).brightness;
                  final overlay = bright == Brightness.dark
                      ? const SystemUiOverlayStyle(
                          statusBarColor: Colors.transparent,
                          statusBarIconBrightness: Brightness.light,
                          statusBarBrightness: Brightness.dark,
                          systemNavigationBarColor: Colors.transparent,
                          systemNavigationBarIconBrightness: Brightness.light,
                          systemNavigationBarDividerColor: Colors.transparent,
                          systemNavigationBarContrastEnforced: false,
                        )
                      : const SystemUiOverlayStyle(
                          statusBarColor: Colors.transparent,
                          statusBarIconBrightness: Brightness.dark,
                          statusBarBrightness: Brightness.light,
                          systemNavigationBarColor: Colors.transparent,
                          systemNavigationBarIconBrightness: Brightness.dark,
                          systemNavigationBarDividerColor: Colors.transparent,
                          systemNavigationBarContrastEnforced: false,
                        );
                  final l10n = AppLocalizations.of(ctx);
                  _syncDesktopTrayIfNeeded(ctx, l10n, settings);

                  // Enforce app font as a default across the tree for Texts without explicit family
                  return AnnotatedRegion<SystemUiOverlayStyle>(
                    value: overlay,
                    child: effectiveAppFont == null
                        ? AppSnackBarOverlay(
                            child: child ?? const SizedBox.shrink(),
                          )
                        : DefaultTextStyle.merge(
                            style: TextStyle(fontFamily: effectiveAppFont),
                            child: AppSnackBarOverlay(
                              child: child ?? const SizedBox.shrink(),
                            ),
                          ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

Widget _selectHome() {
  // Mobile remains the default platform. Desktop is an added platform.
  if (kIsWeb) return const HomePage();
  final isDesktop =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
  return isDesktop ? const DesktopHomePage() : const HomePage();
}

// Overrides logic is implemented within SettingsProvider now.
