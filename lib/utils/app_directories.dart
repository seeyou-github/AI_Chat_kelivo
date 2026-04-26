import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Platform-specific application data directory utilities.
///
/// - Windows/macOS/Linux: use the Application Support (app data) directory
///   provided by `path_provider`.
/// - Android/iOS: keep using the Application Documents directory.
class AppDirectories {
  AppDirectories._();

  static Future<void>? _windowsPortableInit;

  static bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static Future<void> ensureWindowsPortableStorageReady() async {
    if (!_isWindowsDesktop) return;
    _windowsPortableInit ??= _initializeWindowsPortableStorage();
    await _windowsPortableInit;
  }

  static Future<void> _initializeWindowsPortableStorage() async {
    final root = await _getWindowsPortableRootDirectory();
    final configDir = Directory(p.join(root.path, 'Config'));
    final cacheDir = Directory(p.join(root.path, 'cache'));
    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
    }
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    await _migrateWindowsLegacyData(configDir: configDir, cacheDir: cacheDir);
  }

  static Future<Directory> _getWindowsPortableRootDirectory() async {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final root = Directory(p.join(exeDir.path, 'AppData'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  static Future<void> _migrateWindowsLegacyData({
    required Directory configDir,
    required Directory cacheDir,
  }) async {
    final marker = File(p.join(configDir.parent.path, '.portable_storage_migrated_v1'));
    if (await marker.exists()) return;

    final appData = Platform.environment['APPDATA'];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final roamingSource = appData == null
        ? null
        : Directory(p.join(appData, 'com.psyche', 'kelivo'));
    final localSource = localAppData == null
        ? null
        : Directory(p.join(localAppData, 'com.psyche', 'kelivo'));

    if (roamingSource != null && await roamingSource.exists()) {
      await _copyDirectoryContents(roamingSource, configDir);
    }
    if (localSource != null && await localSource.exists()) {
      final legacyCache = Directory(p.join(localSource.path, 'cache'));
      if (await legacyCache.exists()) {
        await _copyDirectoryContents(legacyCache, cacheDir);
      }
      await _copyDirectoryContents(
        localSource,
        configDir,
        skipNames: const {'cache'},
      );
    }

    try {
      await marker.writeAsString('ok', flush: true);
    } catch (_) {}
  }

  static Future<void> _copyDirectoryContents(
    Directory source,
    Directory destination, {
    Set<String> skipNames = const <String>{},
  }) async {
    await for (final entity in source.list(recursive: false, followLinks: false)) {
      final name = p.basename(entity.path);
      if (skipNames.contains(name)) continue;
      if (entity is Directory) {
        final next = Directory(p.join(destination.path, name));
        if (!await next.exists()) {
          await next.create(recursive: true);
        }
        await _copyDirectoryContents(entity, next);
        continue;
      }
      if (entity is File) {
        final target = File(p.join(destination.path, name));
        if (await target.exists()) continue;
        try {
          await entity.copy(target.path);
        } catch (_) {}
      }
    }
  }

  /// Gets the root directory for application data storage.
  ///
  /// - Windows/macOS/Linux: Application Support directory
  /// - Android/iOS: Application Documents directory
  static Future<Directory> getAppDataDirectory() async {
    if (_isWindowsDesktop) {
      await ensureWindowsPortableStorageReady();
      final root = await _getWindowsPortableRootDirectory();
      return Directory(p.join(root.path, 'Config'));
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return await getApplicationSupportDirectory();
      case TargetPlatform.windows:
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return await getApplicationDocumentsDirectory();
    }
  }

  /// Gets the directory for uploaded files.
  static Future<Directory> getUploadDirectory() async {
    final root = await getAppDataDirectory();
    return Directory('${root.path}/upload');
  }

  /// Gets the directory for image files.
  static Future<Directory> getImagesDirectory() async {
    final root = await getAppDataDirectory();
    return Directory('${root.path}/images');
  }

  /// Gets the directory for avatar files.
  static Future<Directory> getAvatarsDirectory() async {
    final root = await getAppDataDirectory();
    return Directory('${root.path}/avatars');
  }

  /// Gets the directory for cache files.
  static Future<Directory> getCacheDirectory() async {
    if (_isWindowsDesktop) {
      await ensureWindowsPortableStorageReady();
      final root = await _getWindowsPortableRootDirectory();
      return Directory(p.join(root.path, 'cache'));
    }
    final root = await getAppDataDirectory();
    return Directory('${root.path}/cache');
  }

  /// Gets the platform-provided application cache directory.
  ///
  /// - Android: /data/user/0/`<package>`/cache
  /// - iOS/macOS: Caches directory
  /// - Windows/Linux: platform cache directory (app-specific on Linux via XDG)
  static Future<Directory> getSystemCacheDirectory() async {
    if (_isWindowsDesktop) {
      return getCacheDirectory();
    }
    return await getApplicationCacheDirectory();
  }

  /// Gets the directory for avatar cache files.
  static Future<Directory> getAvatarCacheDirectory() async {
    final root = await getAppDataDirectory();
    return Directory('${root.path}/cache/avatars');
  }

  /// Get file extension from MIME type
  static String extFromMime(String mime) {
    switch (mime.toLowerCase()) {
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      default:
        return 'png';
    }
  }

  /// Save base64 image data to images directory.
  /// [prefix] is used for filename (e.g. 'img', 'mcp_img').
  /// Returns the saved file path, or null if failed.
  static Future<String?> saveBase64Image(
    String mime,
    String base64Data, {
    String prefix = 'img',
  }) async {
    try {
      final dir = await getImagesDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final cleaned = base64Data.replaceAll(RegExp(r'\s'), '');
      List<int> bytes;
      // Support both standard base64 and URL-safe base64
      if (cleaned.contains('-') || cleaned.contains('_')) {
        bytes = base64Url.decode(cleaned);
      } else {
        bytes = base64Decode(cleaned);
      }
      final ext = extFromMime(mime);
      final path =
          '${dir.path}/${prefix}_${DateTime.now().microsecondsSinceEpoch}.$ext';
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      return path;
    } catch (e) {
      debugPrint('Failed to save image: $e');
      return null;
    }
  }
}
