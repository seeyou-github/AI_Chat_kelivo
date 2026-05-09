import 'dart:io';

import 'package:flutter/services.dart';

class NativeFileSave {
  static const MethodChannel _channel = MethodChannel('app.file_save');

  static Future<bool> saveFileFromPath({
    required String sourcePath,
    String? fileName,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError(
        'Native file save is only supported on Android and iOS.',
      );
    }

    final result = await _channel.invokeMethod<dynamic>('saveFileFromPath', {
      'sourcePath': sourcePath,
      if (fileName != null && fileName.trim().isNotEmpty)
        'fileName': fileName.trim(),
    });
    if (result is bool) return result;
    return result == true;
  }

  static Future<String?> pickPersistableDirectory() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Persistable directory access is only supported on Android.',
      );
    }

    final result = await _channel.invokeMethod<dynamic>(
      'pickPersistableDirectory',
    );
    return result is String && result.trim().isNotEmpty ? result.trim() : null;
  }

  static Future<bool> writeFileToPersistableDirectory({
    required String directoryUri,
    required String sourcePath,
    required String fileName,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Persistable directory access is only supported on Android.',
      );
    }

    final result = await _channel.invokeMethod<dynamic>(
      'writeFileToPersistableDirectory',
      {
        'directoryUri': directoryUri,
        'sourcePath': sourcePath,
        'fileName': fileName,
      },
    );
    if (result is bool) return result;
    return result == true;
  }
}
