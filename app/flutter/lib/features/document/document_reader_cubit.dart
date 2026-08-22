import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/features/document/document_source_picker.dart';
import 'package:video_translator/features/document/epub_presentation_loader.dart';

/// Owns local Document Translation selection and reader presentation state.
///
/// Selecting a source never validates it for processing. EPUB presentation is
/// loaded only by the reader's isolate-backed loader; no processing artifact
/// or Python/JSON-RPC payload is created.
final class DocumentReaderCubit extends Cubit<DocumentReaderLoadState> {
  DocumentReaderCubit({
    DocumentSourcePicker? sourcePicker,
    EpubPresentationLoader? epubPresentationLoader,
  }) : _sourcePicker = sourcePicker ?? const FileSelectorDocumentSourcePicker(),
       _epubPresentationLoader =
           epubPresentationLoader ?? const IsolateEpubPresentationLoader(),
       super(const DocumentReaderNoSource());

  final DocumentSourcePicker _sourcePicker;
  final EpubPresentationLoader _epubPresentationLoader;

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
      if (source.format != DocumentReaderFormat.epub) {
        emit(DocumentReaderReady(source));
        return;
      }
      final content = await _epubPresentationLoader.load(source.path);
      if (!isClosed) {
        emit(EpubDocumentReaderReady(source: source, content: content));
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

  /// Releases EPUB presentation bytes when the workspace is left.
  void releaseEpubPresentation() {
    if (state case EpubDocumentReaderReady(:final source)) {
      emit(DocumentReaderReady(source));
    }
  }

  @override
  Future<void> close() {
    releaseEpubPresentation();
    return super.close();
  }
}
