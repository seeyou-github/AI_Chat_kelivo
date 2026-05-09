import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../models/backup.dart';
import '../../providers/settings_provider.dart';
import '../chat/chat_service.dart';
import '../logging/flutter_logger.dart';
import '../native_file_save.dart';
import 'data_sync.dart';

class AutoBackupService {
  AutoBackupService._();

  static final AutoBackupService instance = AutoBackupService._();
  static const String fileName = 'AIChat_backup.zip';

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
    return Platform.isAndroid
        ? 'android:${settings.autoBackupDirectoryUri ?? ''}'
        : 'file:${settings.autoBackupDirectoryPath ?? ''}';
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

    if (Platform.isAndroid) {
      final uri = settings.autoBackupDirectoryUri;
      if (uri == null || uri.isEmpty) return;
      await NativeFileSave.writeFileToPersistableDirectory(
        directoryUri: uri,
        sourcePath: source.path,
        fileName: fileName,
      );
      return;
    }

    final dirPath = settings.autoBackupDirectoryPath;
    if (dirPath == null || dirPath.isEmpty) return;
    final dir = Directory(dirPath);
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, fileName));
    await source.copy(target.path);
  }
}
