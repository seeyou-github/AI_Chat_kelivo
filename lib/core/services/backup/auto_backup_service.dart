import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../utils/app_directories.dart';
import '../../models/backup.dart';
import '../../providers/settings_provider.dart';
import '../chat/chat_service.dart';
import '../logging/flutter_logger.dart';
import '../native_file_save.dart';
import 'data_sync.dart';

class AutoBackupService {
  AutoBackupService._();

  static final AutoBackupService instance = AutoBackupService._();
  static const String fileNamePrefix = 'AIChat_backup_';
  static const String fileExtension = '.zip';

  final List<Listenable> _sources = <Listenable>[];
  Timer? _debounce;
  SettingsProvider? _settings;
  DataSync? _dataSync;
  String? _lastDirectorySignature;
  bool _registered = false;
  bool _running = false;
  bool _rerunRequested = false;

  void configure({
    required SettingsProvider settings,
    required ChatService chatService,
  }) {
    _settings = settings;
    _dataSync = DataSync(chatService: chatService);
    _lastDirectorySignature = _directorySignature(settings);
  }

  static Future<Directory> backupDirectory() async {
    final dir = await AppDirectories.getBackupDirectory();
    await dir.create(recursive: true);
    return dir;
  }

  void watch(Iterable<Listenable> sources) {
    if (_registered) return;
    _registered = true;
    for (final source in sources) {
      source.addListener(_onChanged);
      _sources.add(source);
    }
  }

  void dispose() {
    _debounce?.cancel();
    _debounce = null;
    for (final source in _sources) {
      source.removeListener(_onChanged);
    }
    _sources.clear();
    _registered = false;
  }

  void _onChanged() {
    final settings = _settings;
    if (settings == null) return;
    final directorySignature = _directorySignature(settings);
    if (directorySignature != _lastDirectorySignature) {
      _lastDirectorySignature = directorySignature;
      return;
    }
    if (!settings.autoBackupConfigured) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      unawaited(runNow(reason: 'settings_changed'));
    });
  }

  String _directorySignature(SettingsProvider settings) {
    return 'fixed:${Platform.resolvedExecutable}';
  }

  Future<void> runNow({String reason = 'manual'}) async {
    final settings = _settings;
    final dataSync = _dataSync;
    if (settings == null || dataSync == null) return;
    if (!settings.autoBackupConfigured) return;

    if (_running) {
      _rerunRequested = true;
      return;
    }

    _running = true;
    try {
      do {
        _rerunRequested = false;
        await _writeBackup(settings, dataSync);
      } while (_rerunRequested);
    } catch (e, st) {
      FlutterLogger.log(
        '[AutoBackup] failed ($reason): $e\n$st',
        tag: 'AutoBackup',
      );
    } finally {
      _running = false;
    }
  }

  Future<void> _writeBackup(SettingsProvider settings, DataSync dataSync) async {
    final source = await dataSync.prepareBackupFile(
      WebDavConfig(
        includeChats: settings.webDavConfig.includeChats,
        includeFiles: settings.webDavConfig.includeFiles,
      ),
    );

    try {
      final localName = _localBackupFileName();
      if (Platform.isAndroid) {
        final uri = settings.autoBackupDirectoryUri;
        if (uri != null && uri.isNotEmpty) {
          await NativeFileSave.writeFileToPersistableDirectory(
            directoryUri: uri,
            sourcePath: source.path,
            fileName: localName,
          );
        }
      } else {
        final dir = await backupDirectory();
        final target = File(p.join(dir.path, localName));
        await source.copy(target.path);
        await _pruneLocalBackups(dir, settings.autoBackupMaxFiles);
      }

      final webdav = settings.webDavConfig;
      if (webdav.autoBackupToWebDav && webdav.url.trim().isNotEmpty) {
        await dataSync.uploadBackupFileToWebDav(
          webdav,
          source,
          fileName: p.basename(source.path),
        );
        await dataSync.pruneWebDavBackups(webdav);
      }
    } finally {
      try {
        await source.delete();
      } catch (_) {}
    }
  }

  String _localBackupFileName() {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return '$fileNamePrefix$timestamp$fileExtension';
  }

  Future<void> _pruneLocalBackups(Directory dir, int maxFiles) async {
    if (maxFiles <= 0 || !await dir.exists()) return;
    final files = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith(fileNamePrefix) && name.endsWith(fileExtension)) {
        files.add(entity);
      }
    }
    files.sort((a, b) {
      final aTime = a.statSync().modified;
      final bTime = b.statSync().modified;
      return bTime.compareTo(aTime);
    });
    for (final file in files.skip(maxFiles)) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}
