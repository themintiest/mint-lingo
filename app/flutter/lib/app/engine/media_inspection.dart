enum MediaStreamKind { video, audio, subtitle, data, attachment, unknown }

final class MediaDimensions {
  const MediaDimensions({required this.width, required this.height});

  final int width;
  final int height;

  factory MediaDimensions.fromJson(Map<String, Object?> json) {
    if (json.keys.toSet().difference(const {'width', 'height'}).isNotEmpty ||
        json.length != 2) {
      throw const FormatException('Invalid media stream dimensions.');
    }
    final width = json['width'];
    final height = json['height'];
    if (!_isPositiveInt(width) || !_isPositiveInt(height)) {
      throw const FormatException('Invalid media stream dimensions.');
    }
    return MediaDimensions(width: width as int, height: height as int);
  }

  @override
  bool operator ==(Object other) =>
      other is MediaDimensions &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

final class MediaStreamMetadata {
  const MediaStreamMetadata({
    required this.index,
    required this.kind,
    required this.codec,
    this.dimensions,
  });

  final int index;
  final MediaStreamKind kind;
  final String codec;
  final MediaDimensions? dimensions;

  factory MediaStreamMetadata.fromJson(Map<String, Object?> json) {
    const allowedKeys = {'index', 'kind', 'codec', 'dimensions'};
    if (json.keys.any((key) => !allowedKeys.contains(key))) {
      throw const FormatException('Invalid media stream metadata.');
    }

    final index = json['index'];
    final kindValue = json['kind'];
    final codec = json['codec'];
    if (!_isNonNegativeInt(index) ||
        kindValue is! String ||
        codec is! String ||
        codec.isEmpty) {
      throw const FormatException('Invalid media stream metadata.');
    }
    final kind = MediaStreamKind.values.where((kind) => kind.name == kindValue);
    if (kind.length != 1) {
      throw const FormatException('Invalid media stream metadata.');
    }

    final dimensionsValue = json['dimensions'];
    final dimensions = switch (dimensionsValue) {
      null => null,
      Map<String, Object?> value => MediaDimensions.fromJson(value),
      _ => throw const FormatException('Invalid media stream metadata.'),
    };
    if ((kind.single == MediaStreamKind.video) != (dimensions != null)) {
      throw const FormatException('Invalid media stream metadata.');
    }
    return MediaStreamMetadata(
      index: index as int,
      kind: kind.single,
      codec: codec,
      dimensions: dimensions,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaStreamMetadata &&
      other.index == index &&
      other.kind == kind &&
      other.codec == codec &&
      other.dimensions == dimensions;

  @override
  int get hashCode => Object.hash(index, kind, codec, dimensions);
}

/// Provider-neutral metadata returned by the `media.inspect` IPC method.
final class MediaInspectionMetadata {
  MediaInspectionMetadata({
    required this.duration,
    required Iterable<MediaStreamMetadata> streams,
    required this.hasAudio,
  }) : streams = List.unmodifiable(streams) {
    if (this.streams.isEmpty ||
        this.streams.map((stream) => stream.index).toSet().length !=
            this.streams.length ||
        hasAudio !=
            this.streams.any(
              (stream) => stream.kind == MediaStreamKind.audio,
            )) {
      throw const FormatException('Invalid media inspection metadata.');
    }
  }

  final Duration duration;
  final List<MediaStreamMetadata> streams;
  final bool hasAudio;

  factory MediaInspectionMetadata.fromJson(Map<String, Object?> json) {
    const requiredKeys = {'durationMicroseconds', 'streams', 'hasAudio'};
    if (json.length != requiredKeys.length ||
        !json.keys.toSet().containsAll(requiredKeys)) {
      throw const FormatException('Invalid media inspection metadata.');
    }
    final durationMicroseconds = json['durationMicroseconds'];
    final streamsValue = json['streams'];
    final hasAudio = json['hasAudio'];
    if (!_isNonNegativeInt(durationMicroseconds) ||
        streamsValue is! List ||
        streamsValue.isEmpty ||
        hasAudio is! bool) {
      throw const FormatException('Invalid media inspection metadata.');
    }
    try {
      return MediaInspectionMetadata(
        duration: Duration(microseconds: durationMicroseconds as int),
        streams: streamsValue.map((stream) {
          if (stream is! Map<String, dynamic>) {
            throw const FormatException('Invalid media stream metadata.');
          }
          return MediaStreamMetadata.fromJson(
            Map<String, Object?>.from(stream),
          );
        }),
        hasAudio: hasAudio,
      );
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Invalid media inspection metadata.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MediaInspectionMetadata &&
      other.duration == duration &&
      _listsEqual(other.streams, streams) &&
      other.hasAudio == hasAudio;

  @override
  int get hashCode => Object.hash(duration, Object.hashAll(streams), hasAudio);
}

enum MediaInspectionErrorType { validation, tool }

/// Structured safe error data returned by the `media.inspect` IPC method.
final class MediaInspectionException implements Exception {
  const MediaInspectionException({
    required this.type,
    required this.code,
    required this.retryable,
  });

  final MediaInspectionErrorType type;
  final String code;
  final bool retryable;

  factory MediaInspectionException.fromResponse({
    required int responseCode,
    required Map<String, Object?>? data,
  }) {
    if (responseCode == -32010 &&
        data?['mediaCode'] is String &&
        data?['retryable'] is bool) {
      return MediaInspectionException(
        type: MediaInspectionErrorType.validation,
        code: data!['mediaCode']! as String,
        retryable: data['retryable']! as bool,
      );
    }
    if (responseCode == -32011 &&
        data?['toolCode'] is String &&
        data?['retryable'] is bool) {
      return MediaInspectionException(
        type: MediaInspectionErrorType.tool,
        code: data!['toolCode']! as String,
        retryable: data['retryable']! as bool,
      );
    }
    throw const FormatException('Invalid media inspection error response.');
  }
}

bool _isNonNegativeInt(Object? value) =>
    value is int && value is! bool && value >= 0;

bool _isPositiveInt(Object? value) =>
    value is int && value is! bool && value > 0;

bool _listsEqual<T>(List<T> first, List<T> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}
