import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages desktop window size persistence and startup placement helpers.
class WindowSizeManager {
  // Constraints
  static const double minWindowWidth = 960.0;
  static const double minWindowHeight = 640.0;
  static const double maxWindowWidth = 8192.0;
  static const double maxWindowHeight = 8192.0;

  // Default (first launch)
  static const double defaultWindowWidth = 1280.0;
  static const double defaultWindowHeight = 860.0;

  // Keys
  static const String _kWidth = 'window_width_v1';
  static const String _kHeight = 'window_height_v1';

  const WindowSizeManager();

  Size _clamp(Size s) {
    final w = s.width.clamp(minWindowWidth, maxWindowWidth);
    final h = s.height.clamp(minWindowHeight, maxWindowHeight);
    return Size(w.toDouble(), h.toDouble());
  }

  @visibleForTesting
  static Offset centerPositionForWorkArea({
    required Rect workArea,
    required Size windowSize,
  }) {
    return Offset(
      workArea.left + (workArea.width - windowSize.width) / 2,
      workArea.top + (workArea.height - windowSize.height) / 2,
    );
  }

  Future<Size> getInitialSize({SharedPreferences? prefs}) async {
    final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
    final width = resolvedPrefs.getDouble(_kWidth) ?? defaultWindowWidth;
    final height = resolvedPrefs.getDouble(_kHeight) ?? defaultWindowHeight;
    return _clamp(Size(width, height));
  }

  Future<Size?> getFastStartupSizeFromPortableConfig() async {
    if (!Platform.isWindows) return null;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final file = File(
        '${exeDir.path}${Platform.pathSeparator}AppData${Platform.pathSeparator}Config${Platform.pathSeparator}shared_preferences.json',
      );
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      return sizeFromPortablePreferencesJson(raw);
    } catch (_) {
      return null;
    }
  }

  Size getDefaultInitialSize() {
    return _clamp(const Size(defaultWindowWidth, defaultWindowHeight));
  }

  Future<void> setSize(Size size) async {
    final prefs = await SharedPreferences.getInstance();
    final s = _clamp(size);
    await prefs.setDouble(_kWidth, s.width);
    await prefs.setDouble(_kHeight, s.height);
  }

  Future<Offset> getCenteredStartupPosition(Size size) async {
    final display = await screenRetriever.getPrimaryDisplay();
    final visiblePosition = display.visiblePosition ?? Offset.zero;
    final visibleSize = display.visibleSize ?? display.size;
    return centerPositionForWorkArea(
      workArea: visiblePosition & visibleSize,
      windowSize: _clamp(size),
    );
  }

  @visibleForTesting
  Size? sizeFromPortablePreferencesJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final width = _portableDouble(decoded, 'flutter.$_kWidth');
      final height = _portableDouble(decoded, 'flutter.$_kHeight');
      if (width == null && height == null) return null;
      return _clamp(
        Size(width ?? defaultWindowWidth, height ?? defaultWindowHeight),
      );
    } catch (_) {
      return null;
    }
  }

  static double? _portableDouble(Map decoded, String key) {
    final value = decoded[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
