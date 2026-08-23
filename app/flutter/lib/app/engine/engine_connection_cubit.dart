import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/engine/engine_client.dart';

enum EngineConnectionStatus { stopped, starting, ready, unavailable, crashed }

class EngineConnectionState {
  const EngineConnectionState._({required this.status, this.info, this.error});

  const EngineConnectionState.stopped()
    : this._(status: EngineConnectionStatus.stopped);

  const EngineConnectionState.starting()
    : this._(status: EngineConnectionStatus.starting);

  const EngineConnectionState.ready(EngineInfo info)
    : this._(status: EngineConnectionStatus.ready, info: info);

  const EngineConnectionState.unavailable(Object error)
    : this._(status: EngineConnectionStatus.unavailable, error: error);

  const EngineConnectionState.crashed(Object error)
    : this._(status: EngineConnectionStatus.crashed, error: error);

  final EngineConnectionStatus status;
  final EngineInfo? info;
  final Object? error;
}

class EngineConnectionCubit extends Cubit<EngineConnectionState> {
  EngineConnectionCubit(this._client)
    : super(const EngineConnectionState.stopped()) {
    _failureSubscription = _client.failures.listen((error) {
      if (!isClosed && state.status != EngineConnectionStatus.stopped) {
        emit(EngineConnectionState.crashed(error));
      }
    });
  }

  final EngineClient _client;
  late final StreamSubscription<Object> _failureSubscription;

  EngineClient get client => _client;

  Future<void> start() async {
    if (state.status == EngineConnectionStatus.starting ||
        state.status == EngineConnectionStatus.ready) {
      return;
    }
    emit(const EngineConnectionState.starting());
    try {
      await _client.start();
      final info = await _client.getInfo();
      if (!isClosed) {
        emit(EngineConnectionState.ready(info));
      }
    } on Object catch (error) {
      if (!isClosed) {
        emit(EngineConnectionState.unavailable(error));
      }
    }
  }

  Future<void> stop() async {
    await _client.stop();
    if (!isClosed) {
      emit(const EngineConnectionState.stopped());
    }
  }

  @override
  Future<void> close() async {
    await _failureSubscription.cancel();
    await _client.dispose();
    return super.close();
  }
}
