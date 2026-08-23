import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/features/document/epub_presentation_loader.dart';

class EpubReaderRegion extends StatefulWidget {
  const EpubReaderRegion({super.key, required this.content});

  final EpubPresentationContent content;

  @override
  State<EpubReaderRegion> createState() => _EpubReaderRegionState();
}

class _EpubReaderRegionState extends State<EpubReaderRegion> {
  var _chapterIndex = 0;

  void _showTableOfContents() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView.builder(
          key: const Key('epub-reader-table-of-contents'),
          itemCount: widget.content.chapters.length,
          itemBuilder: (context, index) {
            final chapter = widget.content.chapters[index];
            return ListTile(
              selected: index == _chapterIndex,
              title: Text(chapter.title),
              onTap: () {
                setState(() => _chapterIndex = index);
                Navigator.of(context).pop();
              },
            );
          },
        ),
      ),
    );
  }

  void _openInternalTarget(String target) {
    final chapterIndex = widget.content.chapters.indexWhere(
      (chapter) => chapter.packagePath == target,
    );
    if (chapterIndex >= 0) {
      setState(() => _chapterIndex = chapterIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.content.chapters[_chapterIndex];
    final isFirst = _chapterIndex == 0;
    final isLast = _chapterIndex == widget.content.chapters.length - 1;

    return Card(
      key: const Key('document-reader-region-epub'),
      child: SizedBox.expand(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('epub-reader-table-of-contents-button'),
                    tooltip: 'Table of contents',
                    onPressed: _showTableOfContents,
                    icon: const Icon(Icons.format_list_bulleted_outlined),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      chapter.title,
                      key: const Key('epub-reader-chapter-title'),
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    key: const Key('epub-reader-previous-chapter'),
                    tooltip: 'Previous chapter',
                    onPressed: isFirst
                        ? null
                        : () => setState(() => _chapterIndex--),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    key: const Key('epub-reader-next-chapter'),
                    tooltip: 'Next chapter',
                    onPressed: isLast
                        ? null
                        : () => setState(() => _chapterIndex++),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                key: const Key('epub-reader-content'),
                padding: const EdgeInsets.all(AppSpacing.xl),
                itemCount: chapter.blocks.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) => EpubBlock(
                  block: chapter.blocks[index],
                  images: widget.content.images,
                  onInternalTarget: _openInternalTarget,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EpubBlock extends StatelessWidget {
  const EpubBlock({
    super.key,
    required this.block,
    required this.images,
    required this.onInternalTarget,
  });

  final EpubPresentationBlock block;
  final Map<String, Uint8List> images;
  final ValueChanged<String> onInternalTarget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = switch (block.kind) {
      EpubPresentationBlockKind.heading => theme.textTheme.headlineSmall,
      EpubPresentationBlockKind.quote => theme.textTheme.bodyLarge?.copyWith(
        fontStyle: FontStyle.italic,
      ),
      EpubPresentationBlockKind.listItem => theme.textTheme.bodyLarge,
      EpubPresentationBlockKind.paragraph => theme.textTheme.bodyLarge,
    };
    final text = <InlineSpan>[];
    for (final inline in block.inlines) {
      if (inline.imagePath case final path?) {
        final image = images[path];
        if (image != null) {
          text.add(
            WidgetSpan(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Image.memory(image, fit: BoxFit.contain),
              ),
            ),
          );
        }
        continue;
      }
      final style = textStyle?.copyWith(
        fontWeight: inline.bold ? FontWeight.bold : null,
        fontStyle: inline.italic ? FontStyle.italic : null,
        decoration: inline.underline ? TextDecoration.underline : null,
        color: inline.internalTarget == null ? null : theme.colorScheme.primary,
      );
      if (inline.internalTarget case final target?) {
        text.add(
          WidgetSpan(
            child: TextButton(
              onPressed: () => onInternalTarget(target),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(inline.text ?? '', style: style),
            ),
          ),
        );
      } else {
        text.add(TextSpan(text: inline.text, style: style));
      }
    }
    return Padding(
      padding: block.kind == EpubPresentationBlockKind.listItem
          ? const EdgeInsets.only(left: AppSpacing.lg)
          : EdgeInsets.zero,
      child: RichText(
        textAlign: block.alignment,
        text: TextSpan(children: text),
      ),
    );
  }
}
