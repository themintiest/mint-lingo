import 'package:flutter/material.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/features/document/plain_text_presentation_loader.dart';

class PlainTextReaderRegion extends StatelessWidget {
  const PlainTextReaderRegion({super.key, required this.content});

  final PlainTextPresentationContent content;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('document-reader-region-plain-text'),
    child: SizedBox.expand(
      child: SelectionArea(
        child: SingleChildScrollView(
          key: const Key('plain-text-reader-content'),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            content.text,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(fontFamily: 'monospace', height: 1.45),
          ),
        ),
      ),
    ),
  );
}
