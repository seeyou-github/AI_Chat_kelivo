import 'dart:io';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/providers/settings_provider.dart';
import '../features/home/services/ocr_service.dart';
import '../features/model/widgets/model_select_sheet.dart' show showModelSelector;
import '../icons/lucide_adapter.dart' as lucide;
import '../utils/app_directories.dart';
import 'hotkeys/ocr_action_bus.dart';

class DesktopOcrPage extends StatefulWidget {
  const DesktopOcrPage({super.key});

  @override
  State<DesktopOcrPage> createState() => _DesktopOcrPageState();
}

class _DesktopOcrPageState extends State<DesktopOcrPage> {
  final TextEditingController _inputController = TextEditingController();
  final OcrService _ocrService = OcrService();
  final List<_OcrEntry> _entries = <_OcrEntry>[];
  final List<String> _imagePaths = <String>[];
  StreamSubscription<OcrAction>? _ocrActionSub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ocrActionSub = OcrActionBus.instance.stream.listen((action) {
      if (!mounted) return;
      switch (action) {
        case OcrAction.captureAndSend:
          _captureScreenshot();
          break;
      }
    });
  }

  @override
  void dispose() {
    _ocrActionSub?.cancel();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final modelLabel = settings.ocrModelKey ?? '选择OCR模型';

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  lucide.Lucide.TextSelect,
                  size: 20,
                  color: cs.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  'OCR文字识别',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    decoration: TextDecoration.none,
                  ),
                ),
                const Spacer(),
                Text(
                  modelLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _entries.isEmpty
                ? Center(
                    child: Text(
                      '上传图片或截图后开始识别',
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _OcrEntryView(entry: _entries[index]);
                    },
                  ),
          ),
          _buildComposer(context),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_imagePaths.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                height: 74,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _imagePaths.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final path = _imagePaths[index];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(path),
                        width: 74,
                        height: 74,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 74,
                          height: 74,
                          color: cs.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Icon(
                            lucide.Lucide.ImageOff,
                            size: 18,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          TextField(
            controller: _inputController,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: '输入补充要求，或直接发送图片进行OCR',
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _ComposerButton(
                tooltip: '模型选择',
                icon: lucide.Lucide.Bot,
                onTap: _busy ? null : _selectOcrModel,
              ),
              const SizedBox(width: 8),
              _ComposerButton(
                tooltip: '截图',
                icon: lucide.Lucide.Camera,
                onTap: _busy ? null : _captureScreenshot,
              ),
              const SizedBox(width: 8),
              _ComposerButton(
                tooltip: '上传文件',
                icon: lucide.Lucide.Paperclip,
                onTap: _busy ? null : _pickImages,
              ),
              const SizedBox(width: 8),
              _ComposerButton(
                tooltip: '清除对话',
                icon: lucide.Lucide.Trash2,
                onTap: _busy ? null : _clearOcrContext,
              ),
              const Spacer(),
              _SendButton(
                busy: _busy,
                onTap: _busy ? null : _sendOcr,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _selectOcrModel() async {
    final selection = await showModelSelector(context);
    if (!mounted || selection == null) return;
    await context.read<SettingsProvider>().setOcrModel(
      selection.providerKey,
      selection.modelId,
    );
  }

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files
        .map((file) => file.path)
        .whereType<String>()
        .where((path) => path.trim().isNotEmpty)
        .toList();
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _imagePaths.addAll(picked);
    });
  }

  Future<void> _captureScreenshot() async {
    if (_busy) return;
    if (!Platform.isWindows) {
      _showMessage('当前平台暂不支持自动截图，请使用上传文件。');
      await _pickImages();
      return;
    }

    setState(() => _busy = true);
    String? screenshotPath;
    try {
      await windowManager.hide();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final cacheDir = await AppDirectories.getCacheDirectory();
      await cacheDir.create(recursive: true);
      final fileName =
          'ocr_screenshot_${DateTime.now().toIso8601String().replaceAll(':', '-')}.png';
      final path = p.join(cacheDir.path, fileName);
      screenshotPath = path;
      final script = _windowsScreenshotScript(path);
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        runInShell: false,
      );
      if (result.exitCode != 0 || !(await File(path).exists())) {
        screenshotPath = null;
      }
    } catch (_) {
      screenshotPath = null;
    } finally {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;
    if (screenshotPath == null) {
      _showMessage('截图失败，请使用上传文件。');
      return;
    }
    final path = screenshotPath;
    setState(() {
      _imagePaths.add(path);
    });
    await _sendOcr();
  }

  String _windowsScreenshotScript(String outputPath) {
    final escaped = outputPath.replaceAll("'", "''");
    return '''
Add-Type -AssemblyName System.Windows.Forms;
Add-Type -AssemblyName System.Drawing;
\$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen;
\$bitmap = New-Object System.Drawing.Bitmap \$bounds.Width, \$bounds.Height;
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap);
\$graphics.CopyFromScreen(\$bounds.Left, \$bounds.Top, 0, 0, \$bounds.Size);
\$bitmap.Save('$escaped', [System.Drawing.Imaging.ImageFormat]::Png);
\$graphics.Dispose();
\$bitmap.Dispose();
''';
  }

  Future<void> _sendOcr() async {
    final settings = context.read<SettingsProvider>();
    if (settings.ocrModelProvider == null || settings.ocrModelId == null) {
      _showMessage('请先选择OCR模型。');
      return;
    }
    final images = List<String>.of(_imagePaths);
    final prompt = _inputController.text.trim();
    if (images.isEmpty && prompt.isEmpty) {
      _showMessage('请先截图、上传图片或输入内容。');
      return;
    }

    setState(() {
      _busy = true;
      _entries.add(
        _OcrEntry(
          role: _OcrRole.user,
          text: prompt.isEmpty ? '识别 ${images.length} 张图片' : prompt,
          imagePaths: images,
        ),
      );
      _inputController.clear();
      _imagePaths.clear();
    });

    final text = images.isEmpty
        ? '没有图片可识别。'
        : await _ocrService.runOcrForImages(images, context);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _entries.add(
        _OcrEntry(
          role: _OcrRole.assistant,
          text: (text == null || text.trim().isEmpty) ? 'OCR识别失败。' : text,
          imagePaths: const <String>[],
        ),
      );
    });
  }

  void _clearOcrContext() {
    _ocrService.clearCache();
    setState(() {
      _entries.clear();
      _imagePaths.clear();
      _inputController.clear();
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

enum _OcrRole { user, assistant }

class _OcrEntry {
  const _OcrEntry({
    required this.role,
    required this.text,
    required this.imagePaths,
  });

  final _OcrRole role;
  final String text;
  final List<String> imagePaths;
}

class _OcrEntryView extends StatelessWidget {
  const _OcrEntryView({required this.entry});

  final _OcrEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser = entry.role == _OcrRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isUser
                ? cs.primary.withValues(alpha: 0.10)
                : cs.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.imagePaths.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final path in entry.imagePaths)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(path),
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 96,
                                height: 96,
                                color: cs.surface,
                                alignment: Alignment.center,
                                child: Icon(
                                  lucide.Lucide.ImageOff,
                                  size: 20,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                Text(
                  entry.text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: cs.onSurface,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerButton extends StatelessWidget {
  const _ComposerButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 18,
              color: onTap == null
                  ? cs.onSurfaceVariant.withValues(alpha: 0.45)
                  : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: '发送',
      child: MouseRegion(
        cursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
            child: busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                : Icon(
                    lucide.Lucide.ArrowUp,
                    size: 20,
                    color: cs.onPrimary,
                  ),
          ),
        ),
      ),
    );
  }
}
