import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/theme/app_colors.dart';
import 'package:video_translator/app/theme/app_radius.dart';
import 'package:video_translator/app/theme/app_theme.dart';

void main() {
  test('defines a consistent desktop workspace visual foundation', () {
    final theme = AppTheme.light;

    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.colorScheme.surfaceContainerLow, AppColors.surfaceSubtle);
    expect(theme.textTheme.titleMedium?.fontWeight, FontWeight.w600);
    expect(theme.textTheme.labelLarge?.fontWeight, FontWeight.w600);
    expect(theme.appBarTheme.scrolledUnderElevation, 0);
    expect(theme.cardTheme.elevation, 0);
    expect(
      theme.cardTheme.shape,
      isA<RoundedRectangleBorder>().having(
        (shape) => shape.borderRadius,
        'border radius',
        BorderRadius.circular(AppRadius.lg),
      ),
    );
    expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
    expect(
      theme.iconButtonTheme.style?.minimumSize?.resolve({}),
      const Size(40, 40),
    );
  });
}
