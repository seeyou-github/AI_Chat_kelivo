import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'window_size_manager.dart';

/// Handles desktop window initialization and size persistence.
class DesktopWindowController with WindowListener {
  DesktopWindowController._();
  static final DesktopWindowController instance = DesktopWindowController._();

  final WindowSizeManager _sizeMgr = const WindowSizeManager();
  bool _attached = false;
  // Debounce resize persistence to avoid frequent disk writes during drag.
  Timer? _resizeDebounce;
  static const _debounceDuration = Duration(milliseconds: 400);

  Future<void> initializeAndShow({
    String? title,
    SharedPreferences? initialPrefs,
    bool centerOnStartup = true,
    bool useDefaultSizeWhenPrefsMissing = false,
  }) async {
    if (kIsWeb) return;
    if (!(defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux)) {
      return;
    }

    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    if (!isWindows) {
      await windowManager.ensureInitialized();
    }
    _attachListeners();
    // Windows custom title bar is handled in main (TitleBarStyle.hidden)
    final initialSize =
        isWindows && useDefaultSizeWhenPrefsMissing && initialPrefs == null
        ? await _sizeMgr.getFastStartupSizeFromPortableConfig() ??
              _sizeMgr.getDefaultInitialSize()
        : useDefaultSizeWhenPrefsMissing && initialPrefs == null
        ? _sizeMgr.getDefaultInitialSize()
        : await _sizeMgr.getInitialSize(prefs: initialPrefs);
    const minSize = Size(
      WindowSizeManager.minWindowWidth,
      WindowSizeManager.minWindowHeight,
    );
    const maxSize = Size(
      WindowSizeManager.maxWindowWidth,
      WindowSizeManager.maxWindowHeight,
    );

    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final options = WindowOptions(
      // On macOS, let Cocoa autosave restore the last frame to avoid jumps.
      size: isMac ? null : initialSize,
      // Avoid imposing min/max on macOS to prevent subtle size corrections.
      minimumSize: isMac ? null : minSize,
      maximumSize: isMac ? null : maxSize,
      title: title,
    );

    if (isWindows) {
      await windowManager.setMinimumSize(minSize);
      await windowManager.setMaximumSize(maxSize);
      await windowManager.setSize(initialSize);
      if (centerOnStartup) {
        try {
          final position = await _sizeMgr.getCenteredStartupPosition(
            initialSize,
          );
          await windowManager.setPosition(position);
        } catch (_) {}
      }
      if (title != null) {
        await windowManager.setTitle(title);
      }
      return;
    }

    await windowManager.waitUntilReadyToShow(options, () async {
      if (!isMac) {
        try {
          final position = await _sizeMgr.getCenteredStartupPosition(
            initialSize,
          );
          await windowManager.setPosition(position);
        } catch (_) {}
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  void _attachListeners() {
    if (_attached) return;
    windowManager.addListener(this);
    _attached = true;
  }

  @override
  void onWindowResize() {
    // Throttle saves while resizing to reduce jank
    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(_debounceDuration, () async {
      await _persistWindowSize();
    });
  }

  @override
  void onWindowResized() async {
    _resizeDebounce?.cancel();
    await _persistWindowSize();
  }

  @override
  void onWindowMove() {
    // Startup is always centered, so move events are intentionally not persisted.
  }

  @override
  void onWindowUnmaximize() async {
    try {
      await _persistWindowSize();
    } catch (_) {}
  }

  @override
  void onWindowLeaveFullScreen() async {
    try {
      await _persistWindowSize();
    } catch (_) {}
  }

  @override
  void onWindowClose() async {
    _resizeDebounce?.cancel();
    await _persistWindowSize();
  }

  Future<void> _persistWindowSize() async {
    try {
      final isMax = await windowManager.isMaximized();
      if (isMax) return;
      final size = await windowManager.getSize();
      await _sizeMgr.setSize(size);
    } catch (_) {}
  }
}
