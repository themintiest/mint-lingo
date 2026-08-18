import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/app.dart';
import 'package:video_translator/app/theme/app_colors.dart';

void main() {
  testWidgets('shows the empty project workspace', (WidgetTester tester) async {
    await tester.pumpWidget(const VideoTranslatorApp());

    expect(find.text('Video Translator'), findsOneWidget);
    expect(find.text('No video is open'), findsOneWidget);
    expect(
      find.text('Open a video to begin a translation project.'),
      findsOneWidget,
    );

    final context = tester.element(find.text('No video is open'));
    expect(Theme.of(context).colorScheme.primary, AppColors.primary);
    expect(Theme.of(context).brightness, Brightness.light);
  });
}
