import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/features/document/pdf_presentation_loader.dart';

void main() {
  test(
    'loads bounded local PDF presentation readiness without retaining bytes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pdf-reader-load-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final fixture = File(
        [directory.path, 'source.pdf'].join(Platform.pathSeparator),
      );
      await fixture.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);

      final content = await const LocalPdfPresentationLoader().load(
        fixture.path,
      );

      expect(content, isA<PdfPresentationContent>());
    },
  );

  test(
    'rejects a PDF over the 50 MiB reader envelope before rendering',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pdf-reader-size-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final fixture = File(
        [directory.path, 'large.pdf'].join(Platform.pathSeparator),
      );
      final handle = await fixture.open(mode: FileMode.write);
      await handle.setPosition(LocalPdfPresentationLoader.maxFileBytes);
      await handle.writeByte(0);
      await handle.close();

      expect(
        () => const LocalPdfPresentationLoader().load(fixture.path),
        throwsA(isA<PdfReaderFileTooLargeException>()),
      );
    },
  );
}
