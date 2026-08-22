import 'package:flutter/material.dart';
import 'package:video_translator/app/app_locale_selector.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

/// The entry boundary for Document Translation before document acquisition.
class DocumentTranslationLauncherPage extends StatelessWidget {
  const DocumentTranslationLauncherPage({
    super.key,
    required this.localeOverride,
    required this.onLocaleSelected,
  });

  static const _maxContentWidth = 520.0;
  static const _compactWidth = 600.0;

  final Locale? localeOverride;
  final ValueChanged<Locale> onLocaleSelected;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.documentTranslationWorkflow),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: AppLocaleSelector(
              localeOverride: localeOverride,
              onLocaleSelected: onLocaleSelected,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < _compactWidth
                ? AppSpacing.lg
                : AppSpacing.xl;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                AppSpacing.xxl,
                horizontalPadding,
                AppSpacing.xxl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                  child: Card(
                    key: const Key('document-translation-launcher'),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              shape: BoxShape.circle,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Icon(
                                Icons.description_outlined,
                                size: 40,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            localizations.documentTranslationWorkflow,
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            localizations.documentLauncherDescription,
                            style: Theme.of(context).textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
