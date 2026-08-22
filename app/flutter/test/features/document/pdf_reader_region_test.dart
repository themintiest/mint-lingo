import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:video_translator/app/theme/app_theme.dart';
import 'package:video_translator/features/document/reader/pdf/pdf_reader_region.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('configures a local-only bounded PDF reader surface', (
    tester,
  ) async {
    String? openedPath;
    PdfViewerParams? capturedParams;

    Widget viewerBuilder(
      String localPath,
      PdfViewerController controller,
      PdfViewerParams params,
    ) {
      openedPath = localPath;
      capturedParams = params;
      return const SizedBox.expand();
    }

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
            localPath: '/documents/source.pdf',
            onLoadFailure: (_) {},
            onPageLimitExceeded: () {},
            viewerBuilder: viewerBuilder,
          ),
        ),
      ),
    );

    expect(openedPath, '/documents/source.pdf');
    expect(capturedParams, isNotNull);
    expect(
      capturedParams!.annotationRenderingMode,
      PdfAnnotationRenderingMode.none,
    );
    expect(capturedParams!.linkHandlerParams, isNull);
    expect(capturedParams!.linkWidgetBuilder, isNull);
    expect(capturedParams!.limitRenderingCache, isTrue);
    expect(
      capturedParams!.maxImageBytesCachedOnMemory,
      PdfReaderRegion.maxImageBytesCachedOnMemory,
    );
    expect(capturedParams!.horizontalCacheExtent, 0);
    expect(capturedParams!.verticalCacheExtent, 0.25);
    expect(
      capturedParams!.sizeDelegateProvider,
      const PdfViewerSizeDelegateProviderLegacy(maxScale: 4),
    );
    expect(find.byKey(const Key('document-reader-region-pdf')), findsOneWidget);
    expect(find.byKey(const Key('pdf-reader-content')), findsOneWidget);
    expect(find.text('Replacing document...'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('pdf-reader-previous-page')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('pdf-reader-zoom-in')))
          .onPressed,
      isNull,
    );
  });
}
