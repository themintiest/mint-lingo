import 'package:flutter_test/flutter_test.dart';
import 'package:video_translator/app/app_workflow.dart';

void main() {
  test('exposes exactly the supported product workflows', () {
    expect(AppWorkflow.values, [
      AppWorkflow.videoTranslation,
      AppWorkflow.documentTranslation,
    ]);
  });
}
