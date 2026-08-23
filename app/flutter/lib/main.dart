import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_translator/app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const VideoTranslatorApp());
}
