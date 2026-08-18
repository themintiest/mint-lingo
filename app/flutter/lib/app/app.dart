import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_translator/app/engine/engine_client.dart';
import 'package:video_translator/app/engine/engine_connection_cubit.dart';
import 'package:video_translator/app/theme/app_theme.dart';
import 'package:video_translator/features/project/media_inspection_cubit.dart';
import 'package:video_translator/features/project/project_setup_cubit.dart';
import 'package:video_translator/features/project/project_workspace_page.dart';

class VideoTranslatorApp extends StatefulWidget {
  const VideoTranslatorApp({
    super.key,
    this.startEngineOnLaunch = true,
    this.engineConnectionCubit,
    this.projectSetupCubit,
    this.mediaInspectionCubit,
  });

  final bool startEngineOnLaunch;
  final EngineConnectionCubit? engineConnectionCubit;
  final ProjectSetupCubit? projectSetupCubit;
  final MediaInspectionCubit? mediaInspectionCubit;

  @override
  State<VideoTranslatorApp> createState() => _VideoTranslatorAppState();
}

class _VideoTranslatorAppState extends State<VideoTranslatorApp> {
  late final EngineConnectionCubit _engineConnectionCubit;
  late final bool _ownsEngineConnectionCubit;
  late final ProjectSetupCubit _projectSetupCubit;
  late final bool _ownsProjectSetupCubit;
  late final MediaInspectionCubit _mediaInspectionCubit;
  late final bool _ownsMediaInspectionCubit;

  @override
  void initState() {
    super.initState();
    _ownsEngineConnectionCubit = widget.engineConnectionCubit == null;
    _engineConnectionCubit =
        widget.engineConnectionCubit ?? EngineConnectionCubit(EngineClient());
    _ownsProjectSetupCubit = widget.projectSetupCubit == null;
    _projectSetupCubit = widget.projectSetupCubit ?? ProjectSetupCubit();
    _ownsMediaInspectionCubit = widget.mediaInspectionCubit == null;
    _mediaInspectionCubit =
        widget.mediaInspectionCubit ??
        MediaInspectionCubit(
          inspectMedia: _engineConnectionCubit.client.inspectMedia,
        );
    if (widget.startEngineOnLaunch) {
      unawaited(_engineConnectionCubit.start());
    }
  }

  @override
  void dispose() {
    if (_ownsEngineConnectionCubit) {
      unawaited(_engineConnectionCubit.close());
    }
    if (_ownsProjectSetupCubit) {
      unawaited(_projectSetupCubit.close());
    }
    if (_ownsMediaInspectionCubit) {
      unawaited(_mediaInspectionCubit.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(

      providers: [
        BlocProvider.value(value: _engineConnectionCubit),
        BlocProvider.value(value: _projectSetupCubit),
        BlocProvider.value(value: _mediaInspectionCubit),
      ],
      child: MaterialApp(
        title: 'Video Translator',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const ProjectWorkspacePage(),
      ),
    );
  }
}
