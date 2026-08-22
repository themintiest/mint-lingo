import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:epubx_kuebiko/epubx_kuebiko.dart';
import 'package:flutter/widgets.dart';
import 'package:xml/xml.dart';

/// The first reader slice retains one bounded, presentation-only EPUB model.
///
/// It deliberately is not an `EpubDocumentArtifact` and carries no processing
/// identity, translation data, validation result, or persistence state.
final class EpubPresentationContent {
  const EpubPresentationContent({required this.chapters, required this.images});

  final List<EpubPresentationChapter> chapters;
  final Map<String, Uint8List> images;
}

final class EpubPresentationChapter {
  const EpubPresentationChapter({
    required this.title,
    required this.packagePath,
    required this.blocks,
  });

  final String title;
  final String packagePath;
  final List<EpubPresentationBlock> blocks;
}

enum EpubPresentationBlockKind { heading, paragraph, listItem, quote }

final class EpubPresentationBlock {
  const EpubPresentationBlock({
    required this.kind,
    required this.alignment,
    required this.inlines,
  });

  final EpubPresentationBlockKind kind;
  final TextAlign alignment;
  final List<EpubPresentationInline> inlines;
}

final class EpubPresentationInline {
  const EpubPresentationInline.text(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.internalTarget,
  }) : imagePath = null;

  const EpubPresentationInline.image(this.imagePath)
    : text = null,
      bold = false,
      italic = false,
      underline = false,
      internalTarget = null;

  final String? text;
  final String? imagePath;
  final bool bold;
  final bool italic;
  final bool underline;

  /// A package-relative, spine-known target. External links are omitted.
  final String? internalTarget;
}

/// Fails safely before in-memory decompression for files outside the reader
/// support envelope.
final class EpubReaderFileTooLargeException implements Exception {
  const EpubReaderFileTooLargeException(this.sizeInBytes);

  final int sizeInBytes;
}

/// Opens a selected local EPUB and produces only reader-presentation data.
abstract interface class EpubPresentationLoader {
  Future<EpubPresentationContent> load(String localPath);
}

final class IsolateEpubPresentationLoader implements EpubPresentationLoader {
  const IsolateEpubPresentationLoader();

  static const maxFileBytes = 50 * 1024 * 1024;

  @override
  Future<EpubPresentationContent> load(String localPath) async {
    final transport = await Isolate.run(() => _loadInIsolate(localPath));
    return _fromTransport(transport);
  }
}

Future<Map<String, Object?>> _loadInIsolate(String localPath) async {
  final file = File(localPath);
  final length = await file.length();
  if (length > IsolateEpubPresentationLoader.maxFileBytes) {
    throw EpubReaderFileTooLargeException(length);
  }

  final book = await EpubReader.readBook(await file.readAsBytes());
  final sourceChapters = <EpubChapter>[];
  void collectChapters(Iterable<EpubChapter>? values) {
    for (final chapter in values ?? const <EpubChapter>[]) {
      sourceChapters.add(chapter);
      collectChapters(chapter.SubChapters);
    }
  }

  collectChapters(book.Chapters);
  final chapterPaths = sourceChapters
      .map((chapter) => _normalizePackagePath(chapter.ContentFileName ?? ''))
      .whereType<String>()
      .toSet();
  if (chapterPaths.isEmpty) {
    throw const FormatException('The EPUB has no readable spine chapters.');
  }

  final imageFiles = <String, Uint8List>{};
  for (final entry
      in book.Content?.Images?.entries ??
          const <MapEntry<String, EpubByteContentFile>>[]) {
    final path = _normalizePackagePath(entry.key);
    final bytes = entry.value.Content;
    if (path != null && bytes != null) {
      imageFiles[path] = Uint8List.fromList(bytes);
    }
  }

  final referencedImages = <String>{};
  final chapters = <Map<String, Object?>>[];
  for (final chapter in sourceChapters) {
    final path = _normalizePackagePath(chapter.ContentFileName ?? '');
    if (path == null) {
      continue;
    }
    final blocks = _sanitizeChapter(
      chapter.HtmlContent ?? '',
      currentPath: path,
      spinePaths: chapterPaths,
      packageImages: imageFiles.keys.toSet(),
      referencedImages: referencedImages,
    );
    chapters.add({
      'title': _safeTitle(chapter.Title, fallback: path),
      'path': path,
      'blocks': blocks,
    });
  }
  if (chapters.isEmpty) {
    throw const FormatException('The EPUB has no readable chapter content.');
  }

  return {
    'chapters': chapters,
    'images': {
      for (final path in referencedImages)
        if (imageFiles.containsKey(path)) path: imageFiles[path]!,
    },
  };
}

List<Map<String, Object?>> _sanitizeChapter(
  String xhtml, {
  required String currentPath,
  required Set<String> spinePaths,
  required Set<String> packageImages,
  required Set<String> referencedImages,
}) {
  final document = XmlDocument.parse(xhtml);
  final body = document.descendants.whereType<XmlElement>().firstWhere(
    (element) => element.name.local.toLowerCase() == 'body',
    orElse: () => document.rootElement,
  );
  final blocks = <Map<String, Object?>>[];
  for (final node in body.children) {
    if (node is! XmlElement) {
      continue;
    }
    _collectBlocks(
      node,
      blocks: blocks,
      currentPath: currentPath,
      spinePaths: spinePaths,
      packageImages: packageImages,
      referencedImages: referencedImages,
    );
  }
  return blocks;
}

void _collectBlocks(
  XmlElement element, {
  required List<Map<String, Object?>> blocks,
  required String currentPath,
  required Set<String> spinePaths,
  required Set<String> packageImages,
  required Set<String> referencedImages,
}) {
  final tag = element.name.local.toLowerCase();
  if (_discardedTags.contains(tag)) {
    return;
  }
  if (!_blockTags.contains(tag)) {
    for (final child in element.children.whereType<XmlElement>()) {
      _collectBlocks(
        child,
        blocks: blocks,
        currentPath: currentPath,
        spinePaths: spinePaths,
        packageImages: packageImages,
        referencedImages: referencedImages,
      );
    }
    return;
  }

  final inlines = <Map<String, Object?>>[];
  _collectInlines(
    element,
    inlines: inlines,
    currentPath: currentPath,
    spinePaths: spinePaths,
    packageImages: packageImages,
    referencedImages: referencedImages,
  );
  if (inlines.isEmpty) {
    return;
  }
  blocks.add({
    'kind': tag.startsWith('h')
        ? 'heading'
        : tag == 'li'
        ? 'list'
        : tag == 'blockquote'
        ? 'quote'
        : 'paragraph',
    'alignment': _alignmentFromStyle(element.getAttribute('style')).name,
    'inlines': inlines,
  });
}

void _collectInlines(
  XmlNode node, {
  required List<Map<String, Object?>> inlines,
  required String currentPath,
  required Set<String> spinePaths,
  required Set<String> packageImages,
  required Set<String> referencedImages,
  bool bold = false,
  bool italic = false,
  bool underline = false,
  String? internalTarget,
}) {
  if (node is XmlText) {
    final text = node.value.replaceAll(RegExp(r'\s+'), ' ');
    if (text.trim().isNotEmpty) {
      inlines.add({
        'text': text,
        'bold': bold,
        'italic': italic,
        'underline': underline,
        'target': internalTarget,
      });
    }
    return;
  }
  if (node is! XmlElement) {
    return;
  }
  final tag = node.name.local.toLowerCase();
  if (_discardedTags.contains(tag)) {
    return;
  }
  if (tag == 'img') {
    final imagePath = normalizeEpubPackageReference(
      currentPath,
      node.getAttribute('src') ?? '',
    );
    if (imagePath != null && packageImages.contains(imagePath)) {
      referencedImages.add(imagePath);
      inlines.add({'image': imagePath});
    }
    return;
  }
  if (tag == 'br') {
    inlines.add({'text': '\n'});
    return;
  }
  if (!_inlineTags.contains(tag) && tag != 'a') {
    for (final child in node.children) {
      _collectInlines(
        child,
        inlines: inlines,
        currentPath: currentPath,
        spinePaths: spinePaths,
        packageImages: packageImages,
        referencedImages: referencedImages,
        bold: bold,
        italic: italic,
        underline: underline,
        internalTarget: internalTarget,
      );
    }
    return;
  }

  final style = node.getAttribute('style') ?? '';
  final linkTarget = tag == 'a'
      ? _safeInternalLink(
          currentPath,
          node.getAttribute('href') ?? '',
          spinePaths,
        )
      : internalTarget;
  for (final child in node.children) {
    _collectInlines(
      child,
      inlines: inlines,
      currentPath: currentPath,
      spinePaths: spinePaths,
      packageImages: packageImages,
      referencedImages: referencedImages,
      bold:
          bold ||
          tag == 'strong' ||
          tag == 'b' ||
          style.contains('font-weight: bold'),
      italic:
          italic ||
          tag == 'em' ||
          tag == 'i' ||
          style.contains('font-style: italic'),
      underline:
          underline ||
          tag == 'u' ||
          style.contains('text-decoration: underline'),
      internalTarget: linkTarget,
    );
  }
}

const _discardedTags = {
  'script',
  'style',
  'form',
  'iframe',
  'frame',
  'object',
  'embed',
  'audio',
  'video',
  'source',
  'track',
  'svg',
  'math',
  'canvas',
  'meta',
  'link',
};
const _blockTags = {
  'p',
  'div',
  'section',
  'article',
  'li',
  'blockquote',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
};
const _inlineTags = {'span', 'strong', 'b', 'em', 'i', 'u', 'code', 'small'};

String _safeTitle(String? title, {required String fallback}) {
  final normalized = title?.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized == null || normalized.isEmpty ? fallback : normalized;
}

String? _safeInternalLink(
  String currentPath,
  String href,
  Set<String> spinePaths,
) {
  if (href.isEmpty || href.startsWith('#')) {
    return spinePaths.contains(currentPath) ? currentPath : null;
  }
  final target = normalizeEpubPackageReference(currentPath, href);
  return target != null && spinePaths.contains(target) ? target : null;
}

/// Resolves only a contained, scheme-free EPUB package reference.
///
/// This is public so focused tests can lock the reader's path-containment
/// policy without exposing parser objects to widgets or state.
String? normalizeEpubPackageReference(String currentPath, String reference) {
  final decoded = Uri.decodeFull(reference);
  final pathOnly = decoded.split('#').first.split('?').first;
  if (pathOnly.isEmpty) {
    return _normalizePackagePath(currentPath);
  }
  if (pathOnly.startsWith('/') ||
      pathOnly.startsWith('\\') ||
      Uri.tryParse(pathOnly)?.hasScheme == true) {
    return null;
  }
  final base = currentPath.split('/')..removeLast();
  return _normalizeSegments(<String>[...base, ...pathOnly.split('/')]);
}

String? _normalizePackagePath(String path) =>
    _normalizeSegments(path.replaceAll('\\', '/').split('/'));

String? _normalizeSegments(List<String> segments) {
  final output = <String>[];
  for (final segment in segments) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (output.isEmpty) {
        return null;
      }
      output.removeLast();
      continue;
    }
    if (segment.contains('\\') || segment.contains(':')) {
      return null;
    }
    output.add(segment);
  }
  return output.isEmpty ? null : output.join('/');
}

TextAlign _alignmentFromStyle(String? style) {
  final value = style?.toLowerCase() ?? '';
  if (value.contains('text-align: center')) return TextAlign.center;
  if (value.contains('text-align: right')) return TextAlign.right;
  if (value.contains('text-align: justify')) return TextAlign.justify;
  return TextAlign.start;
}

EpubPresentationContent _fromTransport(Map<String, Object?> transport) {
  final images = <String, Uint8List>{
    for (final entry in (transport['images']! as Map<Object?, Object?>).entries)
      entry.key! as String: entry.value! as Uint8List,
  };
  final chapters = (transport['chapters']! as List<Object?>)
      .cast<Map<Object?, Object?>>()
      .map((chapter) {
        final blocks = (chapter['blocks']! as List<Object?>)
            .cast<Map<Object?, Object?>>()
            .map((block) {
              final inlines = (block['inlines']! as List<Object?>)
                  .cast<Map<Object?, Object?>>()
                  .map(
                    (inline) => inline.containsKey('image')
                        ? EpubPresentationInline.image(
                            inline['image']! as String,
                          )
                        : EpubPresentationInline.text(
                            inline['text']! as String,
                            bold: inline['bold'] as bool? ?? false,
                            italic: inline['italic'] as bool? ?? false,
                            underline: inline['underline'] as bool? ?? false,
                            internalTarget: inline['target'] as String?,
                          ),
                  )
                  .toList(growable: false);
              return EpubPresentationBlock(
                kind: switch (block['kind']) {
                  'heading' => EpubPresentationBlockKind.heading,
                  'list' => EpubPresentationBlockKind.listItem,
                  'quote' => EpubPresentationBlockKind.quote,
                  _ => EpubPresentationBlockKind.paragraph,
                },
                alignment: TextAlign.values.byName(
                  block['alignment']! as String,
                ),
                inlines: inlines,
              );
            })
            .toList(growable: false);
        return EpubPresentationChapter(
          title: chapter['title']! as String,
          packagePath: chapter['path']! as String,
          blocks: blocks,
        );
      })
      .toList(growable: false);
  return EpubPresentationContent(chapters: chapters, images: images);
}
