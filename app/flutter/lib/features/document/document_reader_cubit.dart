import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/features/document/document_source_picker.dart';

/// Owns local Document Translation selection and reader presentation state.
///
/// Selecting a source does not load its bytes, start a reader, or validate it
/// for processing. A ready state means only that a recognized local source is
/// available for a later format-specific reader surface.
final class DocumentReaderCubit extends Cubit<DocumentReaderLoadState> {
  DocumentReaderCubit({DocumentSourcePicker? sourcePicker})
    : _sourcePicker = sourcePicker ?? const FileSelectorDocumentSourcePicker(),
      super(const DocumentReaderNoSource());

  final DocumentSourcePicker _sourcePicker;

  /// Opens the document-only picker to select or replace one local source.
  Future<void> selectOrReplaceSource() async {
    if (state is DocumentReaderLoading) {
      return;
    }

    final previousState = state;
    emit(DocumentReaderLoading(previousState.source));
    try {
      final source = await _sourcePicker.pickDocumentSource();
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
      emit(DocumentReaderReady(source));
    } on Object catch (error) {
      if (!isClosed) {
        emit(DocumentReaderFailure(source: previousState.source, error: error));
      }
    }
  }
}
