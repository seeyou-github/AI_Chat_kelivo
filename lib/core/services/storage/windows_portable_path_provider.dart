import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../utils/app_directories.dart';

class WindowsPortablePathProvider extends PathProviderPlatform {
  WindowsPortablePathProvider._();

  static bool _installed = false;

  static Future<void> installIfNeeded() async {
    if (_installed || !Platform.isWindows) return;
    await AppDirectories.ensureWindowsPortableStorageReady();
    PathProviderPlatform.instance = WindowsPortablePathProvider._();
    _installed = true;
  }

  @override
  Future<String?> getTemporaryPath() async {
    return (await AppDirectories.getSystemCacheDirectory()).path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return (await AppDirectories.getAppDataDirectory()).path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return (await AppDirectories.getAppDataDirectory()).path;
  }

  @override
  Future<String?> getApplicationCachePath() async {
    return (await AppDirectories.getSystemCacheDirectory()).path;
  }

  @override
  Future<String?> getLibraryPath() async {
    return (await AppDirectories.getAppDataDirectory()).path;
  }

  @override
  Future<String?> getDownloadsPath() async {
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile == null || userProfile.isEmpty) {
      return (await AppDirectories.getAppDataDirectory()).path;
    }
    return '$userProfile${Platform.pathSeparator}Downloads';
  }

  @override
  Future<String?> getExternalStoragePath() async => null;

  @override
  Future<List<String>?> getExternalCachePaths() async => null;

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async => null;
}
