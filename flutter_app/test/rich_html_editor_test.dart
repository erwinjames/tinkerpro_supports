import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinkerpro_support_flutter/theme.dart';
import 'package:tinkerpro_support_flutter/widgets/rich_html_editor.dart';

const _screenshotHtml =
    '<p style="font-size: 16px;">Verify the product&rsquo;s barcode is registered in the POS database.&nbsp;<br>&bull; If barcode is not recognized, register the product in the POS system.</p>\n'
    '<p style="font-size: 16px;"><span style="font-size: 20px; color: rgb(53, 152, 219);">5. Fixing Scanning Issues&nbsp;</span><br>&bull; Clean the scanner lens.</p>';

Widget _host(TextEditingController controller, {VoidCallback? onChanged}) {
  return MaterialApp(
    theme: darkTheme(),
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RichHtmlEditor(
            controller: controller,
            colorPresets: const ['#0C233E'],
            onChanged: onChanged,
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('existing content opens without visible HTML tags', (
    tester,
  ) async {
    final controller = TextEditingController(text: _screenshotHtml);
    await tester.pumpWidget(_host(controller));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('HTML'), findsOneWidget);
    expect(find.textContaining('<p'), findsNothing);
    expect(find.textContaining('&nbsp;'), findsNothing);
    expect(find.textContaining('font-size'), findsNothing);
    expect(controller.text, _screenshotHtml);
  });

  testWidgets('opening a document without editing does not rewrite it', (
    tester,
  ) async {
    var changes = 0;
    final controller = TextEditingController(text: _screenshotHtml);
    await tester.pumpWidget(_host(controller, onChanged: () => changes++));
    await tester.pump(const Duration(milliseconds: 300));
    expect(changes, 0);
    expect(controller.text, _screenshotHtml);
  });

  testWidgets('HTML tab still shows the source', (tester) async {
    final controller = TextEditingController(text: '<p>Hello</p>');
    await tester.pumpWidget(_host(controller));
    await tester.pump();
    await tester.tap(find.text('HTML'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('<p>Hello</p>'), findsOneWidget);
  });

  testWidgets('tables show as a protected block', (tester) async {
    final controller = TextEditingController(
      text: '<p>Before</p><table><tbody><tr><td>Cell</td></tr></tbody></table>',
    );
    await tester.pumpWidget(_host(controller));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Table'), findsOneWidget);
    expect(find.text('Kept as is'), findsOneWidget);
  });

  testWidgets('edits in the visual editor write clean HTML back', (
    tester,
  ) async {
    RichEditorHandle? handle;
    var changes = 0;
    final controller = TextEditingController(text: _screenshotHtml);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme(),
        home: Scaffold(
          body: ListView(
            children: [
              RichHtmlEditor(
                controller: controller,
                colorPresets: const ['#0C233E'],
                onChanged: () => changes++,
                extraTools: (h, _) {
                  handle = h;
                  return const [];
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    handle!.insertHtmlBlock('<p><video src="https://x.io/v.mp4"></video></p>');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(changes, greaterThan(0));
    expect(
      controller.text,
      contains('<video src="https://x.io/v.mp4"></video>'),
    );
    expect(controller.text, contains('color:#3598db'));
    expect(controller.text, contains('font-size:20px'));
    expect(controller.text, contains('Clean the scanner lens.'));
    expect(controller.text, isNot(contains('<p><video')));
    expect(find.text('Video'), findsOneWidget);
  });

  testWidgets('real help topic opens in the visual editor, not HTML', (
    tester,
  ) async {
    final html = File(
      'test/fixtures/help_barcode_scanner.html',
    ).readAsStringSync();
    final controller = TextEditingController(text: html);
    await tester.pumpWidget(_host(controller));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining("can't keep"), findsNothing);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.textContaining('<p'), findsNothing);
    expect(find.textContaining('&bull;'), findsNothing);
    expect(controller.text, html);
  });
}
