import 'package:flutter/material.dart';
import 'package:video_translator/app/theme/app_theme.dart';
import 'package:video_translator/features/project/project_workspace_page.dart';

class VideoTranslatorApp extends StatelessWidget {
  const VideoTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Translator',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const ProjectWorkspacePage(),
    );
  }
}
