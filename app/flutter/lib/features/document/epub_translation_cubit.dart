import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/engine/engine_client.dart';
import 'package:video_translator/common/models/language.dart';
import 'package:video_translator/common/models/model_inventory.dart';
import 'package:video_translator/features/document/document_reader_state.dart';
import 'package:video_translator/features/document/epub_presentation_loader.dart';
import 'package:video_translator/features/processing/processing_bloc.dart';

const epubTranslationWorkflowId = 'document.epub.translate';
const _modelInventoryRequestTimeout = Duration(seconds: 15);

/// EPUB-owned configuration, job lifecycle, and rebuilt-reader state.
///
/// The engine retains all translation and export behavior. This Cubit only
/// serializes local paths and user selections into the concrete EPUB workflow
/// payload, normalizes generic job notifications for shared presentation, and
/// loads a completed local output through the existing reader loader.
final class EpubTranslationCubit extends Cubit<EpubTranslationState> {
  EpubTranslationCubit({
    required this.engine,
    EpubPresentationLoader? presentationLoader,
  }) : _presentationLoader =
           presentationLoader ?? const IsolateEpubPresentationLoader(),
       super(const EpubTranslationState()) {
    _notificationSubscription = engine.notifications.listen(
      _handleNotification,
      onError: _handleEngineFailure,
    );
  }

  final EngineClient engine;
  final EpubPresentationLoader _presentationLoader;
  late final StreamSubscription<EngineNotification> _notificationSubscription;

  void selectSourceLanguage(Language language) => emit(
    state.copyWith(
      sourceLanguage: language,
      clearMessage: true,
      clearFailureDiagnostic: true,
    ),
  );

  void selectTargetLanguage(Language language) => emit(
    state.copyWith(
      targetLanguage: language,
      clearMessage: true,
      clearFailureDiagnostic: true,
    ),
  );

  void selectModelId(String? value) {
    if (value == null ||
        state.modelInventoryStatus != ModelInventoryStatus.ready ||
        !state.modelIds.contains(value)) {
      return;
    }
    emit(
      state.copyWith(
        modelId: value,
        clearMessage: true,
        clearFailureDiagnostic: true,
      ),
    );
  }

  Future<void> refreshModelInventory() async {
    if (state.processing is ProcessingActive) {
      return;
    }
    emit(
      state.copyWith(
        modelInventoryStatus: ModelInventoryStatus.loading,
        clearMessage: true,
        clearFailureDiagnostic: true,
      ),
    );
    try {
      final response = await engine.request(
        'epub.getModels',
        timeout: _modelInventoryRequestTimeout,
      );
      final modelIds = _modelIdsFromWire(response);
      final selectedModelId = modelIds.contains(state.modelId)
          ? state.modelId
          : '';
      emit(
        state.copyWith(
          modelIds: modelIds,
          modelId: selectedModelId,
          modelInventoryStatus: modelIds.isEmpty
              ? ModelInventoryStatus.empty
              : ModelInventoryStatus.ready,
          clearMessage: true,
          clearFailureDiagnostic: true,
        ),
      );
    } on Object catch (_) {
      if (!isClosed) {
        emit(
          state.copyWith(
            modelIds: const [],
            modelInventoryStatus: ModelInventoryStatus.unavailable,
            clearModelId: true,
            clearMessage: true,
            clearFailureDiagnostic: true,
          ),
        );
      }
    }
  }

  void selectReader(EpubReaderVersion value) {
    if (value == EpubReaderVersion.translated &&
        state.translatedContent == null) {
      return;
    }
    emit(state.copyWith(readerVersion: value));
  }

  Future<void> start({
    required DocumentSourceReference source,
    required String destinationPath,
  }) async {
    if (state.processing is ProcessingActive ||
        source.format != DocumentReaderFormat.epub ||
        !state.isConfigured ||
        destinationPath.trim().isEmpty) {
      return;
    }

    final checkpointNamespace = 'epub-${_newUuidV4()}';
    final artifactRoot =
        '${File(destinationPath).parent.path}'
        '${Platform.pathSeparator}.mint-lingo-epub-artifacts';
    try {
      final response = await engine.request(
        'job.start',
        params: {
          'workflowId': epubTranslationWorkflowId,
          'workflowPayload': {
            'sourcePath': source.path,
            'sourceLanguage': state.sourceLanguage!.tag,
            'targetLanguage': state.targetLanguage!.tag,
            'destinationPath': destinationPath,
            'artifactRoot': artifactRoot,
            'checkpointNamespace': checkpointNamespace,
            'provider': {'providerId': 'ollama', 'modelId': state.modelId},
          },
        },
      );
      final job = response['job'];
      if (response.length != 1 || job is! Map<String, dynamic>) {
        throw const EngineProtocolException('Invalid EPUB job start result.');
      }
      final jobId = job['jobId'];
      final lifecycle = _lifecycleFromWire(job['lifecycle']);
      if (job.length != 2 || jobId is! String || lifecycle == null) {
        throw const EngineProtocolException('Invalid EPUB job start result.');
      }
      emit(
        state.copyWith(
          jobId: jobId,
          sourcePath: source.path,
          destinationPath: destinationPath,
          processing: ProcessingActive.created(jobId),
          clearTranslatedContent: true,
          readerVersion: EpubReaderVersion.original,
          clearMessage: true,
          clearFailureDiagnostic: true,
        ),
      );
      _applyLifecycle(jobId, lifecycle);
    } on Object catch (_) {
      if (!isClosed) {
        emit(
          state.copyWith(
            processing: const ProcessingIdle(),
            message: EpubTranslationMessage.startFailed,
          ),
        );
      }
    }
  }

  Future<void> cancel() async {
    final jobId = state.jobId;
    if (jobId == null || state.processing is! ProcessingActive) {
      return;
    }
    emit(
      state.copyWith(
        processing: _withCancellationRequested(state.processing, jobId),
      ),
    );
    try {
      await engine.request('job.cancel', params: {'jobId': jobId});
    } on Object catch (_) {
      if (!isClosed) {
        emit(state.copyWith(message: EpubTranslationMessage.cancelFailed));
      }
    }
  }

  void _handleNotification(EngineNotification notification) {
    final jobId = state.jobId;
    if (jobId == null || notification.params['jobId'] != jobId) {
      return;
    }
    switch (notification.method) {
      case 'job.progress':
        final stageId = notification.params['stageId'];
        final progress = _progressFromWire(notification.params['progress']);
        if (stageId is String && stageId.isNotEmpty && progress != null) {
          final current = state.processing;
          if (current is ProcessingActive &&
              current.lifecycle == ProcessingJobLifecycle.running) {
            emit(
              state.copyWith(
                processing: ProcessingActive(
                  jobId: jobId,
                  lifecycle: current.lifecycle,
                  stageId: stageId,
                  progress: progress,
                  cancellationRequested: current.cancellationRequested,
                ),
              ),
            );
          }
        }
      case 'job.stateChanged':
        final lifecycle = _lifecycleFromWire(notification.params['lifecycle']);
        if (lifecycle != null) {
          _applyLifecycle(jobId, lifecycle);
        }
    }
  }

  void _applyLifecycle(String jobId, ProcessingJobLifecycle lifecycle) {
    final current = state.processing;
    if (current is! ProcessingActive || current.jobId != jobId) {
      return;
    }
    switch (lifecycle) {
      case ProcessingJobLifecycle.created:
        return;
      case ProcessingJobLifecycle.running:
        emit(
          state.copyWith(
            processing: ProcessingActive(
              jobId: jobId,
              lifecycle: lifecycle,
              stageId: current.stageId,
              progress: current.progress,
              cancellationRequested: current.cancellationRequested,
            ),
          ),
        );
      case ProcessingJobLifecycle.failed:
        emit(state.copyWith(processing: ProcessingTerminal(jobId, lifecycle)));
        unawaited(_loadFailureDiagnostic(jobId));
      case ProcessingJobLifecycle.cancelled:
        emit(state.copyWith(processing: ProcessingTerminal(jobId, lifecycle)));
      case ProcessingJobLifecycle.completed:
        emit(
          state.copyWith(
            processing: ProcessingTerminal(jobId, lifecycle),
            message: EpubTranslationMessage.loadingOutput,
          ),
        );
        unawaited(_loadCompletedOutput(jobId));
    }
  }

  Future<void> _loadFailureDiagnostic(String jobId) async {
    try {
      final response = await engine.request(
        'epub.getFailure',
        params: {'jobId': jobId},
      );
      final failure = response['failure'];
      if (response.length != 1 || failure is! Map) {
        throw const EngineProtocolException('Invalid EPUB failure diagnostic.');
      }
      final code = failure['code'];
      final message = failure['message'];
      final retryable = failure['retryable'];
      if (failure.length != 3 ||
          code is! String ||
          code.isEmpty ||
          message is! String ||
          message.isEmpty ||
          retryable is! bool) {
        throw const EngineProtocolException('Invalid EPUB failure diagnostic.');
      }
      if (!isClosed && state.jobId == jobId) {
        emit(
          state.copyWith(
            failureDiagnostic: EpubFailureDiagnostic(
              code: code,
              message: message,
              retryable: retryable,
            ),
            clearMessage: true,
          ),
        );
      }
    } on Object catch (_) {
      if (!isClosed && state.jobId == jobId) {
        emit(state.copyWith(message: EpubTranslationMessage.startFailed));
      }
    }
  }

  Future<void> _loadCompletedOutput(String jobId) async {
    try {
      final response = await engine.request(
        'epub.getExport',
        params: {'jobId': jobId},
      );
      final path = response['exportedArtifactReference'];
      if (response.length != 1 || path is! String || path.isEmpty) {
        throw const EngineProtocolException('Invalid EPUB export reference.');
      }
      final content = await _presentationLoader.load(path);
      if (!isClosed && state.jobId == jobId) {
        emit(
          state.copyWith(
            translatedContent: content,
            readerVersion: EpubReaderVersion.translated,
            clearMessage: true,
          ),
        );
      }
    } on Object catch (_) {
      if (!isClosed && state.jobId == jobId) {
        emit(state.copyWith(message: EpubTranslationMessage.outputLoadFailed));
      }
    }
  }

  void _handleEngineFailure(Object _) {
    if (isClosed || state.processing is! ProcessingActive) {
      return;
    }
    final jobId = state.jobId!;
    emit(
      state.copyWith(
        processing: ProcessingTerminal(jobId, ProcessingJobLifecycle.failed),
        message: EpubTranslationMessage.startFailed,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _notificationSubscription.cancel();
    return super.close();
  }
}

final class EpubTranslationState {
  const EpubTranslationState({
    this.sourceLanguage,
    this.targetLanguage,
    this.modelId = '',
    this.modelIds = const [],
    this.modelInventoryStatus = ModelInventoryStatus.initial,
    this.jobId,
    this.sourcePath,
    this.destinationPath,
    this.processing = const ProcessingIdle(),
    this.translatedContent,
    this.readerVersion = EpubReaderVersion.original,
    this.message,
    this.failureDiagnostic,
  });

  final Language? sourceLanguage;
  final Language? targetLanguage;
  final String modelId;
  final List<String> modelIds;
  final ModelInventoryStatus modelInventoryStatus;
  final String? jobId;
  final String? sourcePath;
  final String? destinationPath;
  final ProcessingState processing;
  final EpubPresentationContent? translatedContent;
  final EpubReaderVersion readerVersion;
  final EpubTranslationMessage? message;
  final EpubFailureDiagnostic? failureDiagnostic;

  bool get isConfigured =>
      sourceLanguage != null &&
      targetLanguage != null &&
      modelInventoryStatus == ModelInventoryStatus.ready &&
      modelIds.contains(modelId);

  EpubTranslationState copyWith({
    Language? sourceLanguage,
    Language? targetLanguage,
    String? modelId,
    List<String>? modelIds,
    ModelInventoryStatus? modelInventoryStatus,
    String? jobId,
    String? sourcePath,
    String? destinationPath,
    ProcessingState? processing,
    EpubPresentationContent? translatedContent,
    EpubReaderVersion? readerVersion,
    EpubTranslationMessage? message,
    EpubFailureDiagnostic? failureDiagnostic,
    bool clearMessage = false,
    bool clearFailureDiagnostic = false,
    bool clearTranslatedContent = false,
    bool clearModelId = false,
  }) => EpubTranslationState(
    sourceLanguage: sourceLanguage ?? this.sourceLanguage,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    modelId: clearModelId ? '' : modelId ?? this.modelId,
    modelIds: List.unmodifiable(modelIds ?? this.modelIds),
    modelInventoryStatus: modelInventoryStatus ?? this.modelInventoryStatus,
    jobId: jobId ?? this.jobId,
    sourcePath: sourcePath ?? this.sourcePath,
    destinationPath: destinationPath ?? this.destinationPath,
    processing: processing ?? this.processing,
    translatedContent: clearTranslatedContent
        ? null
        : translatedContent ?? this.translatedContent,
    readerVersion: readerVersion ?? this.readerVersion,
    message: clearMessage ? null : message ?? this.message,
    failureDiagnostic: clearFailureDiagnostic
        ? null
        : failureDiagnostic ?? this.failureDiagnostic,
  );
}

final class EpubFailureDiagnostic {
  const EpubFailureDiagnostic({
    required this.code,
    required this.message,
    required this.retryable,
  });

  final String code;
  final String message;
  final bool retryable;
}

enum EpubReaderVersion { original, translated }

enum EpubTranslationMessage {
  startFailed,
  cancelFailed,
  loadingOutput,
  outputLoadFailed,
}

ProcessingState _withCancellationRequested(
  ProcessingState state,
  String jobId,
) {
  final active = state as ProcessingActive;
  return ProcessingActive(
    jobId: jobId,
    lifecycle: active.lifecycle,
    stageId: active.stageId,
    progress: active.progress,
    cancellationRequested: true,
  );
}

ProcessingJobLifecycle? _lifecycleFromWire(Object? value) => switch (value) {
  'created' => ProcessingJobLifecycle.created,
  'running' => ProcessingJobLifecycle.running,
  'completed' => ProcessingJobLifecycle.completed,
  'failed' => ProcessingJobLifecycle.failed,
  'cancelled' => ProcessingJobLifecycle.cancelled,
  _ => null,
};

ProcessingProgress? _progressFromWire(Object? value) {
  if (value is! Map<String, dynamic>) {
    return null;
  }
  if (value.length == 1 && value['kind'] == 'indeterminate') {
    return const ProcessingIndeterminateProgress();
  }
  final completed = value['completedUnits'];
  final total = value['totalUnits'];
  if (value.length == 3 &&
      value['kind'] == 'determinate' &&
      completed is int &&
      total is int) {
    try {
      return ProcessingDeterminateProgress(
        completedUnits: completed,
        totalUnits: total,
      );
    } on ArgumentError {
      return null;
    }
  }
  return null;
}

List<String> _modelIdsFromWire(Map<String, Object?> response) {
  final values = response['modelIds'];
  if (response.length != 1 || values is! List) {
    throw const EngineProtocolException('Invalid EPUB model inventory.');
  }
  final modelIds = <String>[];
  for (final value in values) {
    if (value is! String || value.isEmpty || value.trim() != value) {
      throw const EngineProtocolException('Invalid EPUB model inventory.');
    }
    modelIds.add(value);
  }
  if (modelIds.toSet().length != modelIds.length) {
    throw const EngineProtocolException('Invalid EPUB model inventory.');
  }
  return List.unmodifiable(modelIds);
}

String _newUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
