import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/markdown_with_highlight.dart';

Widget _buildHarness({
  required SettingsProvider settings,
  required Widget child,
}) {
  return ChangeNotifierProvider<SettingsProvider>.value(
    value: settings,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

TextStyle? _findTextSpanStyle(
  InlineSpan span,
  String target, [
  TextStyle? inheritedStyle,
]) {
  if (span is! TextSpan) return null;
  final effectiveStyle = inheritedStyle?.merge(span.style) ?? span.style;
  if ((span.text ?? '') == target) {
    return effectiveStyle;
  }
  for (final child in span.children ?? const <InlineSpan>[]) {
    final style = _findTextSpanStyle(child, target, effectiveStyle);
    if (style != null) return style;
  }
  return null;
}

double? _fontSizeForText(WidgetTester tester, String target) {
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    if (widget.data == target) {
      return widget.style?.fontSize;
    }
    final span = widget.textSpan;
    final style = span == null ? null : _findTextSpanStyle(span, target);
    if (style?.fontSize != null) return style!.fontSize;
  }

  for (final element in find.byType(RichText).evaluate()) {
    final widget = element.widget as RichText;
    final style = _findTextSpanStyle(widget.text, target);
    if (style?.fontSize != null) return style!.fontSize;
  }

  for (final element in find.byType(SelectableText).evaluate()) {
    final widget = element.widget as SelectableText;
    if (widget.data == target) {
      return widget.style?.fontSize;
    }
    final span = widget.textSpan;
    final style = span == null ? null : _findTextSpanStyle(span, target);
    if (style?.fontSize != null) return style!.fontSize;
  }

  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MarkdownWithCodeHighlight font sizes', () {
    testWidgets('blockquote and table use code font size while links use body size', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.setMarkdownBaseFontSize(21);
      await settings.setMarkdownCodeFontSize(13);

      const markdown = '''
> 引用文本

| 左列 | 右列 |
| --- | --- |
| 表格内容 | [表格链接](https://example.com/table) |

[正文链接](https://example.com/body)
''';

      await tester.pumpWidget(
        _buildHarness(
          settings: settings,
          child: const MarkdownWithCodeHighlight(text: markdown),
        ),
      );
      await tester.pumpAndSettle();

      expect(_fontSizeForText(tester, '引用文本'), 13);
      expect(_fontSizeForText(tester, '左列'), 13);
      expect(_fontSizeForText(tester, '表格内容'), 13);
      expect(_fontSizeForText(tester, '表格链接'), 13);
      expect(_fontSizeForText(tester, '正文链接'), 21);
    });
  });
}
