import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/features/processing/processing_bloc.dart';
import 'package:video_translator/features/processing/processing_status_panel.dart';
import 'package:video_translator/l10n/generated/app_localizations.dart';

void main() {
  const jobId = '2a0a14c6-670a-4f70-9d95-6847237b0c0c';

  testWidgets('renders a workflow-supplied label and exact known progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        state: ProcessingActive(
          jobId: jobId,
          lifecycle: ProcessingJobLifecycle.running,
          stageId: 'rebuilding_source',
          progress: ProcessingDeterminateProgress(
            completedUnits: 3,
            totalUnits: 8,
          ),
          cancellationRequested: false,
        ),
      ),
    );

    expect(find.text('Restoring the selected source'), findsOneWidget);
    expect(find.text('3 of 8 units'), findsOneWidget);
    expect(find.text('rebuilding_source'), findsNothing);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('processing-progress-determinate')),
          )
          .value,
      3 / 8,
    );
  });

  testWidgets(
    'renders unknown work as indeterminate without a fabricated total',
    (tester) async {
      await tester.pumpWidget(
        _host(
          state: ProcessingActive(
            jobId: jobId,
            lifecycle: ProcessingJobLifecycle.running,
            stageId: 'checking_integrity',
            progress: const ProcessingIndeterminateProgress(),
            cancellationRequested: false,
          ),
        ),
      );

      expect(find.text('Checking the selected source'), findsOneWidget);
      expect(find.text('Working...'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('processing-progress-indeterminate')),
            )
            .value,
        isNull,
      );
      expect(find.byKey(const Key('processing-progress-units')), findsNothing);
    },
  );

  testWidgets('leaves localized stage text to the concrete workflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        locale: const Locale('vi'),
        state: ProcessingActive(
          jobId: jobId,
          lifecycle: ProcessingJobLifecycle.running,
          stageId: 'workflow_owned_stage',
          progress: const ProcessingIndeterminateProgress(),
          cancellationRequested: false,
        ),
        stageLabelBuilder: (context, _) =>
            Localizations.localeOf(context).languageCode == 'vi'
            ? 'Đang kiểm tra nguồn đã chọn'
            : 'Checking the selected source',
      ),
    );

    expect(find.text('Đang kiểm tra nguồn đã chọn'), findsOneWidget);
    expect(find.text('Đang xử lý...'), findsOneWidget);
    expect(find.text('workflow_owned_stage'), findsNothing);
  });

  testWidgets(
    'exposes cancellation as a callback and disables it after acknowledgement',
    (tester) async {
      String? requestedJobId;
      final state = ProcessingActive(
        jobId: jobId,
        lifecycle: ProcessingJobLifecycle.running,
        stageId: 'different_workflow_stage',
        progress: const ProcessingIndeterminateProgress(),
        cancellationRequested: false,
      );

      await tester.pumpWidget(
        _host(
          state: state,
          onCancelRequested: (value) => requestedJobId = value,
        ),
      );
      await tester.tap(find.byKey(const Key('processing-status-cancel')));

      expect(requestedJobId, jobId);

      await tester.pumpWidget(
        _host(
          state: ProcessingActive(
            jobId: jobId,
            lifecycle: ProcessingJobLifecycle.running,
            stageId: 'different_workflow_stage',
            progress: const ProcessingIndeterminateProgress(),
            cancellationRequested: true,
          ),
          onCancelRequested: (value) => requestedJobId = value,
        ),
      );

      expect(find.text('Cancellation requested'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('processing-status-cancel')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'presents terminal failure and cancellation without failure details',
    (tester) async {
      await tester.pumpWidget(
        _host(state: ProcessingTerminal(jobId, ProcessingJobLifecycle.failed)),
      );

      expect(find.byKey(const Key('processing-status-failed')), findsOneWidget);
      expect(find.text('Processing failed.'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          state: ProcessingTerminal(jobId, ProcessingJobLifecycle.cancelled),
        ),
      );

      expect(
        find.byKey(const Key('processing-status-cancelled')),
        findsOneWidget,
      );
      expect(find.text('Processing cancelled.'), findsOneWidget);
    },
  );

  testWidgets('presents both recovery outcomes without selecting a stage', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        state: ProcessingRecovery(
          jobId: jobId,
          disposition: ProcessingRecoveryDisposition.recoverable,
        ),
      ),
    );

    expect(
      find.byKey(const Key('processing-status-recoverable')),
      findsOneWidget,
    );
    expect(find.text('Processing can be recovered.'), findsOneWidget);
    expect(find.byKey(const Key('processing-status-stage')), findsNothing);

    await tester.pumpWidget(
      _host(
        state: ProcessingRecovery(
          jobId: jobId,
          disposition: ProcessingRecoveryDisposition.failed,
        ),
      ),
    );

    expect(
      find.byKey(const Key('processing-status-recovery-failed')),
      findsOneWidget,
    );
    expect(find.text('Processing could not be recovered.'), findsOneWidget);
  });
}

Widget _host({
  required ProcessingState state,
  Locale? locale,
  ValueChanged<String>? onCancelRequested,
  ProcessingStageLabelBuilder? stageLabelBuilder,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: ProcessingStatusPanel(
      state: state,
      stageLabelBuilder:
          stageLabelBuilder ??
          (context, stageId) => switch (stageId) {
            'rebuilding_source' => 'Restoring the selected source',
            'checking_integrity' => 'Checking the selected source',
            'different_workflow_stage' =>
              'Completing a different workflow step',
            _ => throw ArgumentError.value(stageId, 'stageId'),
          },
      onCancelRequested: onCancelRequested,
    ),
  ),
);
