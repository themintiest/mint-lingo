import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/engine/engine_client.dart';
import 'package:video_translator/app/engine/engine_connection_cubit.dart';
import 'package:video_translator/app/theme/app_theme.dart';
import 'package:video_translator/features/project/project_workspace_page.dart';

class VideoTranslatorApp extends StatefulWidget {
  const VideoTranslatorApp({
    super.key,
    this.startEngineOnLaunch = true,
    this.engineConnectionCubit,
  });

  final bool startEngineOnLaunch;
  final EngineConnectionCubit? engineConnectionCubit;

  @override
  State<VideoTranslatorApp> createState() => _VideoTranslatorAppState();
}

class _VideoTranslatorAppState extends State<VideoTranslatorApp> {
  late final EngineConnectionCubit _engineConnectionCubit;
  late final bool _ownsCubit;

  @override
  void initState() {
    super.initState();
    _ownsCubit = widget.engineConnectionCubit == null;
    _engineConnectionCubit =
        widget.engineConnectionCubit ?? EngineConnectionCubit(EngineClient());
    if (widget.startEngineOnLaunch) {
      unawaited(_engineConnectionCubit.start());
    }
  }

  @override
  void dispose() {
    if (_ownsCubit) {
      unawaited(_engineConnectionCubit.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _engineConnectionCubit,
      child: MaterialApp(
        title: 'Video Translator',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const ProjectWorkspacePage(),
      ),
    );
  }
}
