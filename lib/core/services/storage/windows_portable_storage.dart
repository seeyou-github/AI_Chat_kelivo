import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import '../../../utils/app_directories.dart';

class WindowsPortableStorage {
  WindowsPortableStorage._();

  static bool _installed = false;

  static Future<void> installIfNeeded() async {
    if (_installed || !Platform.isWindows) return;
    await AppDirectories.ensureWindowsPortableStorageReady();
    final backend = await _PortablePreferencesBackend.create();
    SharedPreferencesStorePlatform.instance =
        _WindowsPortableSharedPreferencesStore(backend);
    _installed = true;
  }
}

class _WindowsPortableSharedPreferencesStore
    extends SharedPreferencesStorePlatform {
  _WindowsPortableSharedPreferencesStore(this._backend);

  final _PortablePreferencesBackend _backend;

  @override
  Future<bool> clear() async {
    return clearWithPrefix('flutter.');
  }

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    return _backend.mutate((prefs) {
      final keys = prefs.keys
          .where((key) => _matchesFilter(key, parameters.filter))
          .toList(growable: false);
      var changed = false;
      for (final key in keys) {
        changed = prefs.remove(key) != null || changed;
      }
      return changed;
    });
  }

  @override
  Future<bool> clearWithPrefix(String prefix) {
    return clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: prefix)),
    );
  }

  @override
  Future<Map<String, Object>> getAll() async {
    return getAllWithPrefix('flutter.');
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    final prefs = await _backend.readAll();
    final out = <String, Object>{};
    for (final entry in prefs.entries) {
      if (_matchesFilter(entry.key, parameters.filter)) {
        out[entry.key] = entry.value;
      }
    }
    return out;
  }

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) {
    return getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: prefix)),
    );
  }

  @override
  Future<bool> remove(String key) async {
    return _backend.mutate((prefs) => prefs.remove(key) != null);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final normalized = _normalizeValue(value);
    return _backend.mutate((prefs) {
      prefs[key] = normalized;
      return true;
    });
  }

  static bool _matchesFilter(String key, PreferencesFilter filter) {
    if (!key.startsWith(filter.prefix)) return false;
    final allowList = filter.allowList;
    if (allowList == null || allowList.isEmpty) return true;
    if (allowList.contains(key)) return true;
    final unprefixed = key.substring(filter.prefix.length);
    return allowList.contains(unprefixed);
  }

  static Object _normalizeValue(Object value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList(growable: false);
    }
    return value;
  }
}

class _PortablePreferencesBackend {
  _PortablePreferencesBackend._(this._file);

  final File _file;
  Map<String, Object>? _cache;
  Future<void> _queue = Future<void>.value();

  static Future<_PortablePreferencesBackend> create() async {
    final configDir = await AppDirectories.getAppDataDirectory();
    final file = File('${configDir.path}${Platform.pathSeparator}shared_preferences.json');
    final backend = _PortablePreferencesBackend._(file);
    await backend._ensureLoaded();
    return backend;
  }

  Future<Map<String, Object>> readAll() async {
    await _ensureLoaded();
    return Map<String, Object>.from(_cache!);
  }

  Future<bool> mutate(bool Function(Map<String, Object> prefs) action) async {
    final completer = Completer<bool>();
    _queue = _queue.then((_) async {
      await _ensureLoaded();
      final prefs = _cache!;
      final changed = action(prefs);
      if (changed) {
        await _write(prefs);
      }
      completer.complete(changed);
    }).catchError((Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _ensureLoaded() async {
    if (_cache != null) return;
    if (!await _file.exists()) {
      _cache = <String, Object>{};
      return;
    }
    try {
      final raw = await _file.readAsString();
      if (raw.trim().isEmpty) {
        _cache = <String, Object>{};
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _cache = decoded.map<String, Object>((key, value) {
          final normalizedKey = key.toString();
          final normalizedValue = _coerceJsonValue(value);
          return MapEntry(normalizedKey, normalizedValue);
        });
        return;
      }
    } catch (_) {}
    _cache = <String, Object>{};
  }

  Future<void> _write(Map<String, Object> prefs) async {
    final parent = _file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await _file.writeAsString(jsonEncode(prefs), flush: true);
  }

  static Object _coerceJsonValue(Object? value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList(growable: false);
    }
    if (value is bool || value is int || value is double || value is String) {
      return value;
    }
    return value?.toString() ?? '';
  }
}
