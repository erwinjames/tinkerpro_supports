import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tinkerpro_support_flutter/widgets/html_delta.dart';

void main() {
  const samples = <String, String>{
    'paragraph': '<p>Verify the product&rsquo;s barcode is registered.</p>',
    'two paragraphs': '<p>First</p><p>Second</p>',
    'tinymce nested size and rgb colour':
        '<p style="font-size: 16px;"><span style="font-size: 20px; color: rgb(53, 152, 219);">5. Fixing Scanning Issues</span></p>',
    'soft line breaks':
        '<p style="font-size: 16px;">Verify the barcode.&nbsp;<br>&bull; If not recognized, register it.</p>\n<p style="font-size: 16px;"><span style="font-size: 20px; color: rgb(53, 152, 219);">5. Fixing Scanning Issues&nbsp;</span><br>&bull; Clean the lens.&nbsp;<br>&bull; Avoid glare.</p>',
    'bullet list': '<ul><li>Clean the lens</li><li>Avoid glare</li></ul>',
    'nested list': '<ul><li>One<ul><li>Sub</li></ul></li><li>Two</li></ul>',
    'ordered list': '<ol><li>First</li><li>Second</li></ol>',
    'heading': '<h2>Setup</h2><p>Then do this.</p>',
    'link': '<p>See <a href="https://x.io/a">this guide</a>.</p>',
    'image with size':
        '<p><img src="https://x.io/uploads/help/a.png" alt="" width="720" height="400"></p>',
    'table': '<table><tbody><tr><td>A</td><td>B</td></tr></tbody></table>',
    'table mid document':
        '<p>Before</p><table><tbody><tr><td>A</td></tr></tbody></table><p>After</p>',
    'youtube iframe':
        '<p><iframe src="https://www.youtube.com/embed/abc" width="720" height="405" frameborder="0" allowfullscreen="allowfullscreen"></iframe></p>',
    'uploaded video':
        '<p>Before</p><p><video src="https://x.io/v.mp4" controls="controls"></video></p><p>After</p>',
    'centre aligned': '<p style="text-align: center;">Centered</p>',
    'indent': '<p style="padding-left: 40px;">Indented</p>',
    'inline marks':
        '<p><strong>Bold</strong> and <em>italic</em> and <u>under</u> and <s>gone</s></p>',
    'highlight':
        '<p><span style="background-color: #fff3c4;">Marked</span></p>',
    'blog normalised paragraphs':
        '<p style="font-size: 16px;">First paragraph.</p><p style="font-size: 16px;">Second one with <strong>bold</strong>.</p>',
    'blank line': '<p>Above</p><p>&nbsp;</p><p>Below</p>',
    'dividers': '<p>A</p><hr><p>B</p><hr><p>C</p>',
  };

  for (final entry in samples.entries) {
    test('round-trips: ${entry.key}', () {
      expect(htmlSurvivesRoundTrip(entry.value), isTrue);
      final once = htmlToDeltaDocument(entry.value).toHtml();
      final twice = htmlToDeltaDocument(once).toHtml();
      expect(twice, once, reason: 'a second save must not change anything');
    });
  }

  test('opaque blocks are restored byte for byte', () {
    const table =
        '<table style="width: 100%;"><tbody><tr><td>A</td><td>B</td></tr></tbody></table>';
    final out = htmlToDeltaDocument('<p>x</p>$table<p>y</p>').toHtml();
    expect(out, contains(table));
  });

  test('rgb colours become hex, not dropped', () {
    final out = htmlToDeltaDocument(
      '<p><span style="color: rgb(53, 152, 219);">Blue</span></p>',
    ).toHtml();
    expect(out, contains('#3598db'));
  });

  test('soft breaks stay line breaks, not new paragraphs', () {
    final out = htmlToDeltaDocument('<p>A<br>B</p>').toHtml();
    expect(out, '<p>A<br>B</p>');
  });

  test('fingerprint notices real loss', () {
    expect(
      htmlFingerprint('<p>A</p>') == htmlFingerprint('<p>A B</p>'),
      isFalse,
    );
    expect(
      htmlFingerprint('<p style="color: #ff0000">A</p>') ==
          htmlFingerprint('<p>A</p>'),
      isFalse,
    );
  });

  test('real help topic: barcode scanner troubleshooting', () {
    final html = File(
      'test/fixtures/help_barcode_scanner.html',
    ).readAsStringSync();
    expect(htmlSurvivesRoundTrip(html), isTrue);
    final once = htmlToDeltaDocument(html).toHtml();
    expect(htmlToDeltaDocument(once).toHtml(), once);
    expect(once, contains('style="width: 667px; height: auto"'));
    expect(once, contains('width="988" height="299"'));
    expect(once, contains('color:#0066cc'));
    expect(once, contains('<u>Ensure</u>'));
    expect(once, contains('background-color:#ffffff'));
    expect(once, contains('font-size:20px'));
    expect(once, contains('8. Contact Support'));
  });

  test('inline-style underline and bold count as formatting, not loss', () {
    expect(
      htmlSurvivesRoundTrip(
        '<p><a style="text-decoration: underline" href="https://x.io">L</a> '
        '<span style="font-weight: bold">B</span></p>',
      ),
      isTrue,
    );
  });

  test('TinyMCE list items wrapped in paragraphs stay list items', () {
    const html =
        '<ul>\n<li>\n<p>Receipt printer support</p>\n</li>\n<li>\n<p>Offline-ready cart</p>\n</li>\n</ul>';
    expect(htmlSurvivesRoundTrip(html), isTrue);
    expect(
      htmlToDeltaDocument(html).toHtml(),
      '<ul><li>Receipt printer support</li><li>Offline-ready cart</li></ul>',
    );
  });

  test('a bullet holding several paragraphs is refused, not flattened', () {
    const html =
        '<ul><li><p>Automatic updates</p><p><strong>Step 3: Open the APK</strong></p></li></ul>';
    expect(htmlSurvivesRoundTrip(html), isFalse);
    expect(htmlRoundTripIssue(html), 'Step 3: Open the APK');
  });

  test('double line breaks keep their blank line', () {
    const trailing =
        '<p><img src="https://x.io/a.png" width="425" height="172"><br><br></p><p>Next</p>';
    expect(htmlSurvivesRoundTrip(trailing), isTrue);
    expect(htmlToDeltaDocument(trailing).toHtml(), contains('<br><br></p>'));

    const middle = '<p>Above<br><br>Below</p>';
    expect(htmlSurvivesRoundTrip(middle), isTrue);
    expect(htmlToDeltaDocument(middle).toHtml(), '<p>Above<br><br>Below</p>');
  });

  test('a single trailing line break is dropped like browsers do', () {
    expect(htmlToDeltaDocument('<p>Text<br></p>').toHtml(), '<p>Text</p>');
  });
}
