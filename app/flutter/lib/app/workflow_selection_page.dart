import 'package:flutter/material.dart';
import 'package:video_translator/app/app_locale_selector.dart';
import 'package:video_translator/app/app_workflow.dart';
import 'package:video_translator/app/theme/app_spacing.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

/// Lets the application shell ask which concrete translation workflow to open.
///
/// Navigation remains with the application shell so this page only reports the
/// selected product workflow.
class WorkflowSelectionPage extends StatelessWidget {
  const WorkflowSelectionPage({
    super.key,
    required this.onWorkflowSelected,
    this.localeOverride,
    this.onLocaleSelected,
  });

  static const _maxContentWidth = 640.0;
  static const _compactWidth = 600.0;

  final ValueChanged<AppWorkflow> onWorkflowSelected;
  final Locale? localeOverride;
  final ValueChanged<Locale>? onLocaleSelected;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.appTitle),
        actions: [
          if (onLocaleSelected case final onLocaleSelected?)
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
                  child: FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: Column(
                      key: const Key('workflow-selection-page'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          localizations.workflowSelectionQuestion,
                          key: const Key('workflow-selection-question'),
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(1),
                          child: _WorkflowChoice(
                            key: const Key('workflow-video-translation'),
                            icon: Icons.video_file_outlined,
                            label: localizations.videoTranslationWorkflow,
                            onPressed: () => onWorkflowSelected(
                              AppWorkflow.videoTranslation,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(2),
                          child: _WorkflowChoice(
                            key: const Key('workflow-document-translation'),
                            icon: Icons.description_outlined,
                            label: localizations.documentTranslationWorkflow,
                            onPressed: () => onWorkflowSelected(
                              AppWorkflow.documentTranslation,
                            ),
                          ),
                        ),
                      ],
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

class _WorkflowChoice extends StatelessWidget {
  const _WorkflowChoice({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}
