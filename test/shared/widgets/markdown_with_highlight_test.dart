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
  double textScale = 1.0,
}) {
  return ChangeNotifierProvider<SettingsProvider>.value(
    value: settings,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: child),
      ),
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
  if ((span.text ?? '').contains(target)) {
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

int _blockquoteContainerCount(WidgetTester tester) {
  return tester.widgetList<Container>(find.byType(Container)).where((widget) {
    final decoration = widget.decoration;
    if (decoration is! BoxDecoration) return false;
    final border = decoration.border;
    if (border is! Border) return false;
    return border.left.width == 3;
  }).length;
}

double? _richTextScaleForText(WidgetTester tester, String target) {
  final matches = <double>[];

  for (final element in find.byType(RichText).evaluate()) {
    final widget = element.widget as RichText;
    if (widget.text.toPlainText().contains(target)) {
      matches.add(widget.textScaler.scale(1));
    }
  }

  if (matches.isEmpty) return null;
  matches.sort();
  return matches.first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MarkdownWithCodeHighlight font sizes', () {
    testWidgets('blockquote, table, and links follow markdown code font size', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      const initialCodeSize = 13.0;
      const updatedCodeSize = 17.0;
      await settings.setMarkdownBaseFontSize(21);
      await settings.setMarkdownCodeFontSize(initialCodeSize);

      const markdown = '''
> 引用文本
>> 二级引用
>>> 三级引用

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

      void expectMarkdownCodeSize(double expected) {
        expect(_fontSizeForText(tester, '引用文本'), expected);
        expect(_fontSizeForText(tester, '二级引用'), expected);
        expect(_fontSizeForText(tester, '三级引用'), expected);
        expect(_fontSizeForText(tester, '左列'), expected);
        expect(_fontSizeForText(tester, '表格内容'), expected);
        expect(_fontSizeForText(tester, '表格链接'), expected);
        expect(_fontSizeForText(tester, '正文链接'), expected);
      }

      expectMarkdownCodeSize(initialCodeSize);
      expect(_blockquoteContainerCount(tester), greaterThanOrEqualTo(3));

      await settings.setMarkdownCodeFontSize(updatedCodeSize);
      await tester.pump();

      expectMarkdownCodeSize(updatedCodeSize);
      expect(_blockquoteContainerCount(tester), greaterThanOrEqualTo(3));
    });

    testWidgets(
      'nested blockquotes stay aligned with code blocks under chat scale',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsProvider();
        await settings.setChatFontScale(1.5);
        await settings.setMarkdownCodeFontSize(13);

        const markdown = '''
>> 二级引用字号
>>> 三级引用字号

```text
代码字号
```
''';

        await tester.pumpWidget(
          _buildHarness(
            settings: settings,
            textScale: 1.5,
            child: const MarkdownWithCodeHighlight(text: markdown),
          ),
        );
        await tester.pumpAndSettle();

        final level2Scale = _richTextScaleForText(tester, '二级引用字号');
        final level3Scale = _richTextScaleForText(tester, '三级引用字号');

        expect(level2Scale, isNotNull);
        expect(level3Scale, isNotNull);
        expect(level2Scale!, closeTo(1.0, 0.01));
        expect(level3Scale!, closeTo(1.0, 0.01));
      },
    );
  });
}
