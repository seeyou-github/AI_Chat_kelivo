import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme_factory.dart' show getPlatformFontFallback;

enum ConversationColorTarget { text, codeBlock }

enum _ConversationTextTone { light, dark }

Future<void> showConversationTextColorDialog(
  BuildContext context, {
  ConversationColorTarget target = ConversationColorTarget.text,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _ConversationTextColorDialog(target: target),
  );
}

Future<void> showConversationCodeBlockTextColorDialog(
  BuildContext context,
) async {
  await showConversationTextColorDialog(
    context,
    target: ConversationColorTarget.codeBlock,
  );
}

class ConversationTextColorPreview extends StatelessWidget {
  const ConversationTextColorPreview({
    super.key,
    this.showLabels = false,
    this.compact = false,
    this.target = ConversationColorTarget.text,
  });

  final bool showLabels;
  final bool compact;
  final ConversationColorTarget target;

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SettingsProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final active = target == ConversationColorTarget.codeBlock
        ? sp.resolveConversationCodeTextColor(
            theme.brightness,
            fallback: theme.colorScheme.onSurface,
          )
        : sp.resolveConversationTextColor(
            theme.brightness,
            fallback: theme.colorScheme.onSurface,
          );
    final light = target == ConversationColorTarget.codeBlock
        ? sp.conversationCodeTextLightColor
        : sp.conversationTextLightColor;
    final dark = target == ConversationColorTarget.codeBlock
        ? sp.conversationCodeTextDarkColor
        : sp.conversationTextDarkColor;
    final borderColor = theme.colorScheme.outlineVariant.withValues(
      alpha: 0.24,
    );

    Widget chip(_ConversationTextTone tone, Color color, String label) {
      final selected = (tone == _ConversationTextTone.dark) == isDark;
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 4 : 5,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.45) : borderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 12 : 14,
              height: compact ? 12 : 14,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ),
            if (showLabels) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip(
          _ConversationTextTone.light,
          light,
          AppLocalizations.of(context)!.settingsPageLightMode,
        ),
        const SizedBox(width: 6),
        chip(
          _ConversationTextTone.dark,
          dark,
          AppLocalizations.of(context)!.settingsPageDarkMode,
        ),
        if (!compact) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.55,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: borderColor),
            ),
            child: Text(
              _hex(active),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active,
                fontFamilyFallback: getPlatformFontFallback(),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ConversationTextColorDialog extends StatefulWidget {
  const _ConversationTextColorDialog({required this.target});

  final ConversationColorTarget target;

  @override
  State<_ConversationTextColorDialog> createState() =>
      _ConversationTextColorDialogState();
}

class _ConversationTextColorDialogState
    extends State<_ConversationTextColorDialog> {
  _ConversationTextTone _tone = _ConversationTextTone.light;
  late Color _lightColor;
  late Color _darkColor;
  bool _didInitTone = false;

  @override
  void initState() {
    super.initState();
    final sp = context.read<SettingsProvider>();
    _lightColor = widget.target == ConversationColorTarget.codeBlock
        ? sp.conversationCodeTextLightColor
        : sp.conversationTextLightColor;
    _darkColor = widget.target == ConversationColorTarget.codeBlock
        ? sp.conversationCodeTextDarkColor
        : sp.conversationTextDarkColor;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitTone) return;
    _didInitTone = true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _tone = isDark ? _ConversationTextTone.dark : _ConversationTextTone.light;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final current = _tone == _ConversationTextTone.dark
        ? _darkColor
        : _lightColor;
    final isCodeTarget = widget.target == ConversationColorTarget.codeBlock;
    final hsv = HSVColor.fromColor(current);
    final previewBg = _tone == _ConversationTextTone.dark
        ? const Color(0xFF121214)
        : const Color(0xFFFFFFFF);
    final previewText = current;
    final previewStrong = _mixTowards(
      previewText,
      _tone == _ConversationTextTone.dark ? Colors.white : Colors.black,
      0.12,
    );
    final previewSoft = previewText.withValues(alpha: 0.68);
    final previewAccent = Color.lerp(previewText, cs.primary, 0.52) ?? cs.primary;

    return AlertDialog(
      title: Text(
        isCodeTarget
            ? l10n.displaySettingsPageCodeBlockTextColorTitle
            : l10n.displaySettingsPageConversationTextColorDialogTitle,
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_ConversationTextTone>(
              segments: <ButtonSegment<_ConversationTextTone>>[
                ButtonSegment<_ConversationTextTone>(
                  value: _ConversationTextTone.light,
                  label: Text(l10n.settingsPageLightMode),
                ),
                ButtonSegment<_ConversationTextTone>(
                  value: _ConversationTextTone.dark,
                  label: Text(l10n.settingsPageDarkMode),
                ),
              ],
              selected: <_ConversationTextTone>{_tone},
              onSelectionChanged: (selection) {
                setState(() => _tone = selection.first);
              },
            ),
            const SizedBox(height: 14),
            isCodeTarget
                ? _buildCodePreviewCard(
                    l10n: l10n,
                    cs: cs,
                    previewBg: previewBg,
                    previewText: previewText,
                    previewSoft: previewSoft,
                    previewStrong: previewStrong,
                    current: current,
                  )
                : _buildTextPreviewCard(
                    l10n: l10n,
                    cs: cs,
                    previewBg: previewBg,
                    previewText: previewText,
                    previewSoft: previewSoft,
                    previewStrong: previewStrong,
                    previewAccent: previewAccent,
                    current: current,
                  ),
            const SizedBox(height: 14),
            _HsvSliderRow(
              label: 'H',
              value: hsv.hue,
              max: 360,
              displayValue: hsv.hue.round().toString(),
              onChanged: (value) => _setCurrentColor(
                hsv.withHue(value).toColor(),
              ),
            ),
            _HsvSliderRow(
              label: 'S',
              value: hsv.saturation * 100,
              max: 100,
              displayValue: '${(hsv.saturation * 100).round()}%',
              onChanged: (value) => _setCurrentColor(
                hsv.withSaturation(value / 100).toColor(),
              ),
            ),
            _HsvSliderRow(
              label: 'V',
              value: hsv.value * 100,
              max: 100,
              displayValue: '${(hsv.value * 100).round()}%',
              onChanged: (value) => _setCurrentColor(
                hsv.withValue(value / 100).toColor(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            final sp = context.read<SettingsProvider>();
            final toneBrightness = _tone == _ConversationTextTone.dark
                ? Brightness.dark
                : Brightness.light;
            if (isCodeTarget) {
              sp.resetConversationCodeTextColor(toneBrightness);
            } else {
              sp.resetConversationTextColor(toneBrightness);
            }
            setState(() {
              if (_tone == _ConversationTextTone.dark) {
                _darkColor = isCodeTarget
                    ? sp.conversationCodeTextDarkColor
                    : sp.conversationTextDarkColor;
              } else {
                _lightColor = isCodeTarget
                    ? sp.conversationCodeTextLightColor
                    : sp.conversationTextLightColor;
              }
            });
          },
          child: Text(l10n.displaySettingsPageFontResetLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.assistantEditEmojiDialogCancel),
        ),
        FilledButton(
          onPressed: () async {
            final sp = context.read<SettingsProvider>();
            if (isCodeTarget) {
              await sp.setConversationCodeTextLightColor(_lightColor);
              await sp.setConversationCodeTextDarkColor(_darkColor);
            } else {
              await sp.setConversationTextLightColor(_lightColor);
              await sp.setConversationTextDarkColor(_darkColor);
            }
            if (!mounted) return;
            Navigator.of(context).pop();
          },
          child: Text(l10n.assistantEditEmojiDialogSave),
        ),
      ],
    );
  }

  void _setCurrentColor(Color color) {
    setState(() {
      if (_tone == _ConversationTextTone.dark) {
        _darkColor = color;
      } else {
        _lightColor = color;
      }
    });
  }

  Widget _buildTextPreviewCard({
    required AppLocalizations l10n,
    required ColorScheme cs,
    required Color previewBg,
    required Color previewText,
    required Color previewSoft,
    required Color previewStrong,
    required Color previewAccent,
    required Color current,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: previewBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.22)),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: previewText,
          fontSize: 15,
          height: 1.45,
          fontFamilyFallback: getPlatformFontFallback(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.displaySettingsPageConversationTextColorPreview,
              style: TextStyle(
                color: previewSoft,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text('Preview text'),
            const SizedBox(height: 6),
            RichText(
              text: TextSpan(
                style: TextStyle(
                  color: previewText,
                  fontSize: 15,
                  height: 1.45,
                  fontFamilyFallback: getPlatformFontFallback(),
                ),
                children: [
                  TextSpan(
                    text: 'Bold',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: previewStrong,
                    ),
                  ),
                  const TextSpan(text: '  ·  '),
                  TextSpan(
                    text: 'Emphasis',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: previewStrong,
                    ),
                  ),
                  const TextSpan(text: '  ·  '),
                  TextSpan(
                    text: 'Link',
                    style: TextStyle(
                      color: previewAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _hex(current),
              style: TextStyle(
                color: previewStrong,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodePreviewCard({
    required AppLocalizations l10n,
    required ColorScheme cs,
    required Color previewBg,
    required Color previewText,
    required Color previewSoft,
    required Color previewStrong,
    required Color current,
  }) {
    final headerBg = Color.alphaBlend(
      cs.primary.withValues(alpha: 0.12),
      previewBg,
    );
    final bodyBg = Color.alphaBlend(
      cs.primary.withValues(alpha: 0.04),
      previewBg,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: previewBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.displaySettingsPageConversationTextColorPreview,
            style: TextStyle(
              color: previewSoft,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.20),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: headerBg,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'dart',
                          style: TextStyle(
                            color: previewStrong,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          l10n.shareProviderSheetCopyButton,
                          style: TextStyle(
                            color: previewSoft,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    color: bodyBg,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Text(
                      'final answer = 42;\nprint(answer);',
                      style: TextStyle(
                        color: previewText,
                        fontSize: 13,
                        height: 1.35,
                        fontFamily: 'monospace',
                        fontFamilyFallback: getPlatformFontFallback(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _hex(current),
            style: TextStyle(
              color: previewStrong,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HsvSliderRow extends StatelessWidget {
  const _HsvSliderRow({
    required this.label,
    required this.value,
    required this.max,
    required this.displayValue,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final String displayValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(
            label,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.78),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            min: 0,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            displayValue,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.72),
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

Color _mixTowards(Color color, Color target, double amount) =>
    Color.lerp(color, target, amount.clamp(0.0, 1.0)) ?? color;
