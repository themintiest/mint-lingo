import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/engine/engine_client.dart';
import 'package:video_translator/common/models/language.dart';
import 'package:video_translator/features/document/document_presentation.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/features/document/epub_presentation_loader.dart';
import 'package:video_translator/features/document/epub_translation_cubit.dart';
import 'package:video_translator/features/document/epub_translation_workspace.dart';
import 'package:video_translator/features/processing/processing_bloc.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

void main() {
  test(
    'starts EPUB payload, follows lifecycle, and opens only exported output',
    () async {
      final engine = _FakeEngineClient();
      final loader = _FakeEpubPresentationLoader();
      final cubit = EpubTranslationCubit(
        engine: engine,
        presentationLoader: loader,
      );
      addTearDown(() async {
        await cubit.close();
        await engine.close();
      });

      cubit.selectSourceLanguage(Language(tag: 'en'));
      cubit.selectTargetLanguage(Language(tag: 'vi'));
      cubit.setModelId('qwen2.5:7b');
      await cubit.start(
        source: const DocumentSourceReference(
          path: r'C:\books\source.epub',
          fileName: 'source.epub',
          format: DocumentReaderFormat.epub,
        ),
        destinationPath: r'C:\books\translated.epub',
      );

      final start = engine.requests.single;
      expect(start.method, 'job.start');
      final payload = start.params['workflowPayload'] as Map<String, Object?>;
      expect(start.params['workflowId'], epubTranslationWorkflowId);
      expect(payload['sourcePath'], r'C:\books\source.epub');
      expect(payload['destinationPath'], r'C:\books\translated.epub');
      expect(payload['sourceLanguage'], 'en');
      expect(payload['targetLanguage'], 'vi');
      expect(payload['provider'], {
        'providerId': 'ollama',
        'modelId': 'qwen2.5:7b',
      });
      expect(cubit.state.processing, isA<ProcessingActive>());

      engine.notify(
        const EngineNotification(
          method: 'job.stateChanged',
          params: {'jobId': _FakeEngineClient.jobId, 'lifecycle': 'running'},
        ),
      );
      engine.notify(
        const EngineNotification(
          method: 'job.progress',
          params: {
            'jobId': _FakeEngineClient.jobId,
            'stageId': 'translating_epub',
            'progress': {'kind': 'indeterminate'},
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        (cubit.state.processing as ProcessingActive).stageId,
        'translating_epub',
      );

      engine.notify(
        const EngineNotification(
          method: 'job.stateChanged',
          params: {'jobId': _FakeEngineClient.jobId, 'lifecycle': 'completed'},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(engine.requests.last.method, 'epub.getExport');
      expect(loader.loadedPaths, [r'C:\books\translated.epub']);
      expect(cubit.state.translatedContent, same(loader.content));
      expect(cubit.state.readerVersion, EpubReaderVersion.translated);
    },
  );

  test(
    'does not start a non-EPUB source or incomplete configuration',
    () async {
      final engine = _FakeEngineClient();
      final cubit = EpubTranslationCubit(engine: engine);
      addTearDown(() async {
        await cubit.close();
        await engine.close();
      });

      await cubit.start(
        source: const DocumentSourceReference(
          path: r'C:\books\source.txt',
          fileName: 'source.txt',
          format: DocumentReaderFormat.plainText,
        ),
        destinationPath: r'C:\books\translated.epub',
      );

      expect(engine.requests, isEmpty);
    },
  );

  testWidgets('displays the safe EPUB failure diagnostic after a failed job', (
    tester,
  ) async {
    final engine = _FakeEngineClient()
      ..failureResponse = const {
        'failure': {
          'code': 'epub.provider_unavailable',
          'message': 'Ollama could not translate this EPUB. Confirm it is running and the selected model is installed, then try again.',
          'retryable': true,
        },
      };
    final cubit = EpubTranslationCubit(engine: engine);
    addTearDown(() async {
      await cubit.close();
      await engine.close();
    });
    cubit.selectSourceLanguage(Language(tag: 'en'));
    cubit.selectTargetLanguage(Language(tag: 'vi'));
    cubit.setModelId('qwen2.5:14b');

    await cubit.start(
      source: const DocumentSourceReference(
        path: r'C:\books\source.epub',
        fileName: 'source.epub',
        format: DocumentReaderFormat.epub,
      ),
      destinationPath: r'C:\books\translated.epub',
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 736,
            height: 800,
            child: BlocProvider.value(
              value: cubit,
              child: EpubTranslationWorkspace(
                source: const DocumentSourceReference(
                  path: r'C:\books\source.epub',
                  fileName: 'source.epub',
                  format: DocumentReaderFormat.epub,
                ),
                presentation: const EpubDocumentPresentation(
                  content: EpubPresentationContent(
                    chapters: [
                      EpubPresentationChapter(
                        title: 'Original',
                        packagePath: 'text/chapter.xhtml',
                        blocks: [],
                      ),
                    ],
                    images: {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    engine.notify(
      const EngineNotification(
        method: 'job.stateChanged',
        params: {'jobId': _FakeEngineClient.jobId, 'lifecycle': 'failed'},
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(engine.requests.last.method, 'epub.getFailure');
    expect(
      find.text(
        'Ollama could not translate this EPUB. Confirm it is running and the selected model is installed, then try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('epub.provider_unavailable'), findsOneWidget);
    expect(find.text('You can try again.'), findsOneWidget);
  });

  testWidgets('keeps the reader bounded when EPUB configuration is expanded', (
    tester,
  ) async {
    final engine = _FakeEngineClient();
    final cubit = EpubTranslationCubit(engine: engine);
    addTearDown(() async {
      await cubit.close();
      await engine.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 736,
              height: 340,
              child: BlocProvider.value(
                value: cubit,
                child: EpubTranslationWorkspace(
                  source: const DocumentSourceReference(
                    path: r'C:\books\source.epub',
                    fileName: 'source.epub',
                    format: DocumentReaderFormat.epub,
                  ),
                  presentation: const EpubDocumentPresentation(
                    content: EpubPresentationContent(
                      chapters: [
                        EpubPresentationChapter(
                          title: 'Original',
                          packagePath: 'text/chapter.xhtml',
                          blocks: [],
                        ),
                      ],
                      images: {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Translate EPUB').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('document-reader-region-epub')),
      findsOneWidget,
    );
  });
}

final class _FakeEngineClient extends EngineClient {
  _FakeEngineClient()
    : super(startWorker: () => Future<Process>.error(StateError('unused')));

  static const jobId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  final StreamController<EngineNotification> _controller =
      StreamController<EngineNotification>.broadcast();
  final List<_Request> requests = [];
  Map<String, Object?>? failureResponse;

  @override
  Stream<EngineNotification> get notifications => _controller.stream;

  @override
  Future<Map<String, Object?>> request(
    String method, {
    Map<String, Object?>? params,
  }) async {
    requests.add(_Request(method, params ?? const {}));
    return switch (method) {
      'job.start' => {
        'job': {'jobId': jobId, 'lifecycle': 'created'},
      },
      'epub.getExport' => {
        'exportedArtifactReference': r'C:\books\translated.epub',
      },
      'epub.getFailure' =>
        failureResponse ??
            (throw StateError('Unexpected EPUB failure diagnostic request.')),
      'job.cancel' => {'jobId': jobId, 'cancellationRequested': true},
      _ => throw StateError('Unexpected method: $method'),
    };
  }

  void notify(EngineNotification notification) => _controller.add(notification);

  Future<void> close() => _controller.close();
}

final class _Request {
  const _Request(this.method, this.params);

  final String method;
  final Map<String, Object?> params;
}

final class _FakeEpubPresentationLoader implements EpubPresentationLoader {
  final List<String> loadedPaths = [];
  final EpubPresentationContent content = const EpubPresentationContent(
    chapters: [
      EpubPresentationChapter(
        title: 'Translated',
        packagePath: 'text/chapter.xhtml',
        blocks: [],
      ),
    ],
    images: {},
  );

  @override
  Future<EpubPresentationContent> load(String localPath) async {
    loadedPaths.add(localPath);
    return content;
  }
}
