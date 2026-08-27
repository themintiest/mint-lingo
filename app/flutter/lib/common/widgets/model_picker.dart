import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_translator/common/models/model_inventory.dart';

/// Localized text for a reusable installed-model picker.
class ModelPickerText {
  const ModelPickerText({
    required this.label,
    required this.hint,
    required this.loading,
    required this.empty,
    required this.unavailable,
    required this.refresh,
  });

  final String label;
  final String hint;
  final String loading;
  final String empty;
  final String unavailable;
  final String refresh;
}

/// A refreshable picker for a workspace-owned installed-model inventory.
///
/// The widget is provider-neutral: callers own inventory discovery, labels,
/// and selection validation. [keyPrefix] lets a workspace keep stable,
/// distinct widget-test identifiers when needed.
class ModelPicker extends StatelessWidget {
  const ModelPicker({
    super.key,
    required this.status,
    required this.modelIds,
    required this.selectedModelId,
    required this.enabled,
    required this.onSelected,
    required this.onRefresh,
    required this.text,
    this.keyPrefix,
  });

  final ModelInventoryStatus status;
  final List<String> modelIds;
  final String selectedModelId;
  final bool enabled;
  final ValueChanged<String?> onSelected;
  final Future<void> Function() onRefresh;
  final ModelPickerText text;
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    if (status == ModelInventoryStatus.ready) {
      return Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey(
                '${keyPrefix ?? 'model-picker'}-dropdown-'
                '$selectedModelId-${modelIds.join('|')}',
              ),
              initialValue: modelIds.contains(selectedModelId)
                  ? selectedModelId
                  : null,
              decoration: InputDecoration(
                labelText: text.label,
                hintText: text.hint,
                border: const OutlineInputBorder(),
              ),
              items: modelIds
                  .map(
                    (modelId) =>
                        DropdownMenuItem(value: modelId, child: Text(modelId)),
                  )
                  .toList(),
              onChanged: enabled ? onSelected : null,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: _key('refresh'),
            tooltip: text.refresh,
            onPressed: enabled ? () => unawaited(onRefresh()) : null,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      );
    }

    final loading =
        status == ModelInventoryStatus.initial ||
        status == ModelInventoryStatus.loading;
    final message = loading
        ? text.loading
        : status == ModelInventoryStatus.empty
        ? text.empty
        : text.unavailable;
    final messageKey = loading
        ? 'loading'
        : status == ModelInventoryStatus.empty
        ? 'empty'
        : 'unavailable';
    return Row(
      children: [
        if (loading) ...[
          const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(child: Text(key: _key(messageKey), message)),
        if (!loading) ...[
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: _key('refresh'),
            onPressed: enabled ? () => unawaited(onRefresh()) : null,
            icon: const Icon(Icons.refresh_outlined),
            label: Text(text.refresh),
          ),
        ],
      ],
    );
  }

  Key? _key(String suffix) =>
      keyPrefix == null ? null : Key('$keyPrefix-$suffix');
}
