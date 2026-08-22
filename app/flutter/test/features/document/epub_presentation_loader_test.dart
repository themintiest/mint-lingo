import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/features/document/epub_presentation_loader.dart';

void main() {
  test('resolves only package-contained relative resources', () {
    expect(
      normalizeEpubPackageReference('Text/chapter.xhtml', '../Images/a.png'),
      'Images/a.png',
    );
    expect(
      normalizeEpubPackageReference('Text/chapter.xhtml', 'next.xhtml#part-2'),
      'Text/next.xhtml',
    );
    expect(
      normalizeEpubPackageReference('Text/chapter.xhtml', '#part-2'),
      'Text/chapter.xhtml',
    );
  });

  test('rejects external, absolute, and traversal package references', () {
    for (final reference in const [
      'https://example.com/image.png',
      'mailto:reader@example.com',
      '/Images/a.png',
      '../../outside.png',
      '..%2F..%2Foutside.png',
      'C:/outside.png',
      '\\server\\share\\outside.png',
    ]) {
      expect(
        normalizeEpubPackageReference('Text/chapter.xhtml', reference),
        isNull,
        reason: reference,
      );
    }
  });

  test('keeps reader content presentation-only', () {
    const chapter = EpubPresentationChapter(
      title: 'Chapter one',
      packagePath: 'Text/chapter.xhtml',
      blocks: [],
    );
    final content = EpubPresentationContent(
      chapters: const [chapter],
      images: {
        'Images/a.png': Uint8List.fromList([1, 2, 3]),
      },
    );

    expect(content.chapters.single.title, 'Chapter one');
    expect(content.images.values.single, isA<Uint8List>());
  });

  test('rejects an EPUB over 50 MiB before reading or decompression', () async {
    final directory = await Directory.systemTemp.createTemp(
      'epub-reader-size-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final fixture = File(
      '${directory.path}${Platform.pathSeparator}too-large.epub',
    );
    final handle = await fixture.open(mode: FileMode.write);
    await handle.setPosition(IsolateEpubPresentationLoader.maxFileBytes);
    await handle.writeFrom(const [0]);
    await handle.close();

    await expectLater(
      const IsolateEpubPresentationLoader().load(fixture.path),
      throwsA(isA<EpubReaderFileTooLargeException>()),
    );
  });

  test('decodes and sanitizes a local EPUB off the widget boundary', () async {
    final directory = await Directory.systemTemp.createTemp(
      'epub-reader-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final fixture = File(
      '${directory.path}${Platform.pathSeparator}fixture.epub',
    );
    await fixture.writeAsBytes(_minimalEpubFixture());

    final content = await const IsolateEpubPresentationLoader().load(
      fixture.path,
    );

    expect(content.chapters, hasLength(2));
    expect(content.chapters.first.title, 'First chapter');
    expect(
      content.chapters.first.blocks
          .expand((block) => block.inlines)
          .where((inline) => inline.text?.contains('next chapter') ?? false)
          .single
          .internalTarget,
      'Text/chapter-two.xhtml',
    );
    expect(
      content.chapters.first.blocks
          .expand((block) => block.inlines)
          .where((inline) => inline.text?.contains('external') ?? false)
          .single
          .internalTarget,
      isNull,
    );
    expect(
      content.chapters.first.blocks
          .expand((block) => block.inlines)
          .any((inline) => inline.text?.contains('never render') ?? false),
      isFalse,
    );
    final styledBlock = content.chapters.first.blocks.firstWhere(
      (block) => block.inlines.any(
        (inline) => inline.text?.contains('styled') ?? false,
      ),
    );
    expect(styledBlock.alignment, TextAlign.center);
    final styledInline = styledBlock.inlines.firstWhere(
      (inline) => inline.text?.contains('styled') ?? false,
    );
    expect(styledInline.bold, isTrue);
    expect(styledInline.underline, isTrue);
    expect(content.images, contains('Images/pixel.png'));
    expect(content.images, hasLength(1));
  });
}

List<int> _minimalEpubFixture() {
  final archive = Archive();
  void addText(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  addText('mimetype', 'application/epub+zip');
  addText('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''');
  addText('OEBPS/content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="book-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Fixture</dc:title></metadata>
  <manifest>
    <item id="chapter-one" href="Text/chapter-one.xhtml" media-type="application/xhtml+xml"/>
    <item id="chapter-two" href="Text/chapter-two.xhtml" media-type="application/xhtml+xml"/>
    <item id="image" href="Images/pixel.png" media-type="image/png"/>
    <item id="toc" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="toc"><itemref idref="chapter-one"/><itemref idref="chapter-two"/></spine>
</package>''');
  addText('OEBPS/toc.ncx', '''<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head/><docTitle><text>Fixture</text></docTitle><navMap>
    <navPoint id="one" playOrder="1"><navLabel><text>First chapter</text></navLabel><content src="Text/chapter-one.xhtml"/></navPoint>
    <navPoint id="two" playOrder="2"><navLabel><text>Second chapter</text></navLabel><content src="Text/chapter-two.xhtml"/></navPoint>
  </navMap>
</ncx>''');
  addText('OEBPS/Text/chapter-one.xhtml', '''<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml"><body>
  <h1>First chapter</h1><p>Hello <a href="chapter-two.xhtml">next chapter</a>.</p>
  <p><a href="https://example.com">external</a></p><script>never render</script>
  <p style="text-align: center"><span style="font-weight: bold; text-decoration: underline">styled</span></p>
  <p><img src="../Images/pixel.png" alt="pixel"/></p>
  <p><img src="https://example.com/remote.png" alt="remote"/></p>
</body></html>''');
  addText(
    'OEBPS/Text/chapter-two.xhtml',
    '''<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Second chapter</h1></body></html>''',
  );
  archive.addFile(ArchiveFile('OEBPS/Images/pixel.png', 3, [1, 2, 3]));
  return ZipEncoder().encode(archive);
}
