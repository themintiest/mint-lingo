import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

typedef PdfReaderViewerBuilder = Widget Function(
  String localPath,
  PdfViewerController controller,
  PdfViewerParams params,
);

/// Read-only original-source PDF presentation backed by local PDFium rendering.
///
/// The region deliberately accepts only the selected local path. It has no URL
/// source, link handler, browser launch, form/annotation rendering, extraction,
/// editing, or processing behavior.
class PdfReaderRegion extends StatefulWidget {
  const PdfReaderRegion({
    super.key,
    required this.localPath,
    required this.onLoadFailure,
    required this.onPageLimitExceeded,
    this.viewerBuilder,
  });

  static const maxPageCount = 500;
  static const maxImageBytesCachedOnMemory = 32 * 1024 * 1024;

  final String localPath;
  final ValueChanged<Object> onLoadFailure;
  final VoidCallback onPageLimitExceeded;
  final PdfReaderViewerBuilder? viewerBuilder;

  @override
  State<PdfReaderRegion> createState() => _PdfReaderRegionState();
}

class _PdfReaderRegionState extends State<PdfReaderRegion> {
  final _controller = PdfViewerController();
  late final PdfViewerParams _params;
  var _currentPage = 1;
  int? _pageCount;
  var _reportedLoadFailure = false;

  @override
  void initState() {
    super.initState();
    _params = PdfViewerParams(
      annotationRenderingMode: PdfAnnotationRenderingMode.none,
      limitRenderingCache: true,
      maxImageBytesCachedOnMemory: PdfReaderRegion.maxImageBytesCachedOnMemory,
      horizontalCacheExtent: 0,
      verticalCacheExtent: 0.25,
      onePassRenderingSizeThreshold: 1600,
      sizeDelegateProvider: const PdfViewerSizeDelegateProviderLegacy(
        maxScale: 4,
      ),
      onDocumentLoadFinished: (_, succeeded) {
        if (!succeeded) {
          _reportLoadFailure();
        }
      },
      onViewerReady: (document, _) {
        final pageCount = document.pages.length;
        if (pageCount > PdfReaderRegion.maxPageCount) {
          widget.onPageLimitExceeded();
          return;
        }
        if (mounted) {
          setState(() => _pageCount = pageCount);
        }
      },
      onPageChanged: (pageNumber) {
        if (mounted && pageNumber != null) {
          setState(() => _currentPage = pageNumber);
        }
      },
    );
  }

  void _reportLoadFailure() {
    if (_reportedLoadFailure) {
      return;
    }
    _reportedLoadFailure = true;
    widget.onLoadFailure(
      StateError(
        'The selected local PDF could not be opened for presentation.',
      ),
    );
  }

  void _goToPage(int pageNumber) {
    final pageCount = _pageCount;
    if (!_controller.isReady ||
        pageCount == null ||
        pageNumber < 1 ||
        pageNumber > pageCount) {
      return;
    }
    unawaited(_controller.goToPage(pageNumber: pageNumber));
  }

  void _zoomIn() {
    if (_controller.isReady) {
      unawaited(_controller.zoomUp());
    }
  }

  void _zoomOut() {
    if (_controller.isReady) {
      unawaited(_controller.zoomDown());
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final pageCount = _pageCount;
    final isReady = pageCount != null;

    return Card(
      key: const Key('document-reader-region-pdf'),
      child: SizedBox.expand(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('pdf-reader-previous-page'),
                    tooltip: localizations.pdfReaderPreviousPage,
                    onPressed: isReady && _currentPage > 1
                        ? () => _goToPage(_currentPage - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    key: const Key('pdf-reader-next-page'),
                    tooltip: localizations.pdfReaderNextPage,
                    onPressed: isReady && _currentPage < pageCount
                        ? () => _goToPage(_currentPage + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      isReady
                          ? localizations.pdfReaderPageStatus(
                              _currentPage,
                              pageCount,
                            )
                          : localizations.replacingDocument,
                      key: const Key('pdf-reader-page-status'),
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    key: const Key('pdf-reader-zoom-out'),
                    tooltip: localizations.pdfReaderZoomOut,
                    onPressed: isReady ? _zoomOut : null,
                    icon: const Icon(Icons.zoom_out),
                  ),
                  IconButton(
                    key: const Key('pdf-reader-zoom-in'),
                    tooltip: localizations.pdfReaderZoomIn,
                    onPressed: isReady ? _zoomIn : null,
                    icon: const Icon(Icons.zoom_in),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: KeyedSubtree(
                key: const Key('pdf-reader-content'),
                child: (widget.viewerBuilder ?? _buildPdfViewer)(
                  widget.localPath,
                  _controller,
                  _params,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildPdfViewer(
    String localPath,
    PdfViewerController controller,
    PdfViewerParams params,
  ) => PdfViewer.file(localPath, controller: controller, params: params);
}
