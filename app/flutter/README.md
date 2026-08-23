# Video Translator Flutter application

The desktop UI and application orchestration layer for Video Translator.

## Development

Install Flutter, enable the desktop target for your operating system, and run:

```sh
flutter pub get
flutter run -d windows # Use linux or macos on those platforms.
```

Validate changes with:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Product features and communication with the Python engine are intentionally not
part of the initial bootstrap.
