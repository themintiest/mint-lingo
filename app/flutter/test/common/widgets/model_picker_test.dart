import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/common/models/model_inventory.dart';
import 'package:video_translator/common/widgets/model_picker.dart';

void main() {
  const text = ModelPickerText(
    label: 'Model',
    hint: 'Choose an installed model',
    loading: 'Loading models',
    empty: 'No models are installed',
    unavailable: 'Models are unavailable',
    refresh: 'Refresh models',
  );

  testWidgets('renders a selectable inventory and refresh action', (
    tester,
  ) async {
    var refreshes = 0;
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelPicker(
            status: ModelInventoryStatus.ready,
            modelIds: const ['model-one', 'model-two'],
            selectedModelId: 'model-one',
            enabled: true,
            onSelected: (value) => selected = value,
            onRefresh: () async {
              refreshes += 1;
            },
            text: text,
            keyPrefix: 'shared-model',
          ),
        ),
      ),
    );

    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('model-one'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shared-model-refresh')));
    await tester.pump();

    expect(refreshes, 1);
    expect(selected, isNull);
  });

  testWidgets('renders an actionable unavailable state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelPicker(
            status: ModelInventoryStatus.unavailable,
            modelIds: const [],
            selectedModelId: '',
            enabled: true,
            onSelected: (_) {},
            onRefresh: () async {},
            text: text,
            keyPrefix: 'shared-model',
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('shared-model-unavailable')), findsOneWidget);
    expect(find.byKey(const Key('shared-model-refresh')), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });
}
