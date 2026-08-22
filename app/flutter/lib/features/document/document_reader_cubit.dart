import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/features/document/document_source_picker.dart';
import 'package:video_translator/features/document/epub_presentation_loader.dart';
import 'package:video_translator/features/document/plain_text_presentation_loader.dart';

/// Owns local Document Translation selection and reader presentation state.
///
/// Selecting a source never validates it for processing. EPUB presentation is
/// loaded only by the reader's isolate-backed loader; no processing artifact
/// or Python/JSON-RPC payload is created.
final class DocumentReaderCubit extends Cubit<DocumentReaderLoadState> {
  DocumentReaderCubit({
    DocumentSourcePicker? sourcePicker,
    EpubPresentationLoader? epubPresentationLoader,
    PlainTextPresentationLoader? plainTextPresentationLoader,
  }) : _sourcePicker = sourcePicker ?? const FileSelectorDocumentSourcePicker(),
       _epubPresentationLoader =
           epubPresentationLoader ?? const IsolateEpubPresentationLoader(),
       _plainTextPresentationLoader =
           plainTextPresentationLoader ??
           const IsolatePlainTextPresentationLoader(),
       super(const DocumentReaderNoSource());

  final DocumentSourcePicker _sourcePicker;
  final EpubPresentationLoader _epubPresentationLoader;
  final PlainTextPresentationLoader _plainTextPresentationLoader;

  /// Opens the document-only picker to select or replace one local source.
  Future<void> selectOrReplaceSource() async {
    if (state is DocumentReaderLoading) {
      return;
    }

    final previousState = state;
    DocumentSourceReference? selectedSource;
    emit(DocumentReaderLoading(previousState.source));
    try {
      final source = await _sourcePicker.pickDocumentSource();
      selectedSource = source;
      if (isClosed) {
        return;
      }
      if (source == null) {
        emit(previousState);
        return;
      }
      if (source.format == null) {
        emit(DocumentReaderUnsupported(source));
        return;
      }
      if (source.format == DocumentReaderFormat.epub) {
        final content = await _epubPresentationLoader.load(source.path);
        if (!isClosed) {
          emit(EpubDocumentReaderReady(source: source, content: content));
        }
        return;
      }
      if (source.format == DocumentReaderFormat.plainText) {
        final content = await _plainTextPresentationLoader.load(source.path);
        if (!isClosed) {
          emit(PlainTextDocumentReaderReady(source: source, content: content));
        }
        return;
      }
      if (source.format == DocumentReaderFormat.pdf) {
        emit(DocumentReaderReady(source));
        return;
      }
    } on EpubReaderFileTooLargeException {
      if (!isClosed) {
        final source = selectedSource ?? state.source;
        if (source != null) {
          emit(
            DocumentReaderUnsupported(
              source,
              reason: DocumentReaderUnsupportedReason.epubFileTooLarge,
            ),
          );
        }
      }
    } on PlainTextReaderFileTooLargeException {
      _emitUnsupported(
        selectedSource,
        DocumentReaderUnsupportedReason.plainTextFileTooLarge,
      );
    } on PlainTextReaderUnsupportedContentException {
      _emitUnsupported(
        selectedSource,
        DocumentReaderUnsupportedReason.plainTextUnsupportedContent,
      );
    } on Object catch (error) {
      if (!isClosed) {
        emit(
          DocumentReaderFailure(
            source: selectedSource ?? previousState.source,
            error: error,
          ),
        );
      }
    }
  }

  void _emitUnsupported(
    DocumentSourceReference? source,
    DocumentReaderUnsupportedReason reason,
  ) {
    if (!isClosed && source != null) {
      emit(DocumentReaderUnsupported(source, reason: reason));
    }
  }

  /// Releases format-specific presentation content when the workspace is left.
  void releaseReaderPresentation() {
    final source = switch (state) {
      EpubDocumentReaderReady(:final source) => source,
      PlainTextDocumentReaderReady(:final source) => source,
      _ => null,
    };
    if (source != null) {
      emit(DocumentReaderReady(source));
    }
  }

  @override
  Future<void> close() {
    releaseReaderPresentation();
    return super.close();
  }
}
