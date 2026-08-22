import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/features/document/plain_text_presentation_loader.dart';

void main() {
  test(
    'loads UTF-8 text, removes a BOM, and preserves visible blank lines',
    () async {
      final fixture = await _writeTemporaryFile('utf8.txt', [
        0xEF,
        0xBB,
        0xBF,
        ...'First line\n\nSecond line'.codeUnits,
      ]);
      addTearDown(() => fixture.parent.delete(recursive: true));

      final content = await const IsolatePlainTextPresentationLoader().load(
        fixture.path,
      );

      expect(content.text, 'First line\n\nSecond line');
    },
  );

  test('rejects binary and invalid UTF-8 text content', () async {
    final binary = await _writeTemporaryFile('binary.txt', [0x48, 0, 0x49]);
    final invalidUtf8 = await _writeTemporaryFile('invalid.txt', [0xC3, 0x28]);
    addTearDown(() => binary.parent.delete(recursive: true));
    addTearDown(() => invalidUtf8.parent.delete(recursive: true));

    await expectLater(
      const IsolatePlainTextPresentationLoader().load(binary.path),
      throwsA(isA<PlainTextReaderUnsupportedContentException>()),
    );
    await expectLater(
      const IsolatePlainTextPresentationLoader().load(invalidUtf8.path),
      throwsA(isA<PlainTextReaderUnsupportedContentException>()),
    );
  });

  test('rejects files over the 10 MiB reader limit before decoding', () async {
    final directory = await Directory.systemTemp.createTemp('txt-reader-size-');
    addTearDown(() => directory.delete(recursive: true));
    final fixture = File('${directory.path}${Platform.pathSeparator}large.txt');
    final handle = await fixture.open(mode: FileMode.write);
    await handle.setPosition(IsolatePlainTextPresentationLoader.maxFileBytes);
    await handle.writeFrom(const [0]);
    await handle.close();

    await expectLater(
      const IsolatePlainTextPresentationLoader().load(fixture.path),
      throwsA(isA<PlainTextReaderFileTooLargeException>()),
    );
  });
}

Future<File> _writeTemporaryFile(String fileName, List<int> bytes) async {
  final directory = await Directory.systemTemp.createTemp('txt-reader-test-');
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes);
  return file;
}
