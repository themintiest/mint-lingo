import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:video_translator/app/theme/app_theme.dart';
import 'package:video_translator/features/document/reader/pdf/pdf_reader_region.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

void main() {
  // pdfrx documents command-line initialization as the test configuration.
  setUp(pdfrxInitialize);

  testWidgets(
    'renders and navigates a local PDF fixture without activating links',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'pdf-reader-native-',
      );
      addTearDown(() => directory.delete(recursive: true));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });
      final fixture = File(
        [directory.path, 'original-source.pdf'].join(Platform.pathSeparator),
      );
      await fixture.writeAsBytes(_twoPagePdfFixture());

      Object? loadFailure;
      var pageLimitExceeded = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PdfReaderRegion(
              localPath: fixture.path,
              onLoadFailure: (error) => loadFailure = error,
              onPageLimitExceeded: () => pageLimitExceeded = true,
            ),
          ),
        ),
      );

      await _waitForReader(tester, find.text('Page 1 of 2'));
      expect(loadFailure, isNull);
      expect(pageLimitExceeded, isFalse);
      expect(find.text('Page 1 of 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pdf-reader-next-page')));
      await _waitForReader(tester, find.text('Page 2 of 2'));
      expect(find.text('Page 2 of 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pdf-reader-zoom-in')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(loadFailure, isNull);
    },
  );
}

Future<void> _waitForReader(WidgetTester tester, Finder expected) async {
  for (var index = 0; index < 20 && expected.evaluate().isEmpty; index++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

Uint8List _twoPagePdfFixture() {
  const firstPage = 'BT /F1 24 Tf 72 720 Td (First page) Tj ET';
  const secondPage = 'BT /F1 24 Tf 72 720 Td (Second page) Tj ET';
  final firstPageLength = firstPage.length;
  final secondPageLength = secondPage.length;
  final objects = <int, String>{
    1: '<< /Type /Catalog /Pages 2 0 R /OpenAction 9 0 R >>',
    2: '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>',
    3: '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 6 0 R /Annots [8 0 R] >>',
    4: '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    5: '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 7 0 R >>',
    6: '<< /Length $firstPageLength >>\nstream\n$firstPage\nendstream',
    7: '<< /Length $secondPageLength >>\nstream\n$secondPage\nendstream',
    8: '<< /Type /Annot /Subtype /Link /Rect [72 700 220 730] /A << /S /URI /URI (https://example.invalid/) >> >>',
    9: "<< /S /JavaScript /JS (app.alert\\('blocked'\\)) >>",
  };
  final bytes = BytesBuilder(copy: false);
  final offsets = List<int>.filled(objects.length + 1, 0);
  final objectCount = objects.length + 1;

  void write(String value) => bytes.add(ascii.encode(value));

  write('%PDF-1.4\n');
  for (final entry in objects.entries) {
    offsets[entry.key] = bytes.length;
    final objectNumber = entry.key;
    final objectContents = entry.value;
    write('$objectNumber 0 obj\n$objectContents\nendobj\n');
  }
  final xrefOffset = bytes.length;
  write('xref\n0 $objectCount\n0000000000 65535 f \n');
  for (var objectNumber = 1; objectNumber <= objects.length; objectNumber++) {
    final paddedOffset = offsets[objectNumber].toString().padLeft(10, '0');
    write('$paddedOffset 00000 n \n');
  }
  write(
    'trailer\n<< /Size $objectCount /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n',
  );
  return bytes.toBytes();
}
