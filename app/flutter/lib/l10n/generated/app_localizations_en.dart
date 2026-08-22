// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get languageEnglish => 'English';

  @override
  String get languageVietnamese => 'Vietnamese';

  @override
  String get languageJapanese => 'Japanese';

  @override
  String get languageKorean => 'Korean';

  @override
  String get languageChineseSimplified => 'Chinese (Simplified)';

  @override
  String get languageChineseTraditional => 'Chinese (Traditional)';

  @override
  String get languagePortugueseBrazil => 'Portuguese (Brazil)';

  @override
  String get languagePortuguesePortugal => 'Portuguese (Portugal)';

  @override
  String get languageFrench => 'French';

  @override
  String get languageGerman => 'German';

  @override
  String get languageSpanish => 'Spanish';

  @override
  String get languageItalian => 'Italian';

  @override
  String get languageRussian => 'Russian';

  @override
  String get languageHindi => 'Hindi';

  @override
  String get languageArabic => 'Arabic';

  @override
  String get languageThai => 'Thai';

  @override
  String get languageIndonesian => 'Indonesian';

  @override
  String get emptyWorkspaceTitle => 'Start a translation project';

  @override
  String get emptyWorkspaceDescription =>
      'Open a local video to inspect its media and choose translation languages.';

  @override
  String get openVideoEmptyState => 'Open a video';

  @override
  String get selectingVideoEmptyState => 'Selecting video...';

  @override
  String get appTitle => 'Video Translator';

  @override
  String get sourceLanguage => 'Source language';

  @override
  String get targetLanguage => 'Target language';

  @override
  String get automaticDetection => 'Automatic detection';

  @override
  String get noTargetLanguageSelected => 'No target language selected';

  @override
  String get selectSourceLanguage => 'Select source language';

  @override
  String get selectTargetLanguage => 'Select target language';

  @override
  String get autoDetect => 'Auto-detect';

  @override
  String get openingVideoPreview => 'Opening video preview...';

  @override
  String get videoPreviewUnavailable => 'Video preview is unavailable.';

  @override
  String get preparingVideoPreview => 'Preparing video preview...';

  @override
  String get skipBackTenSeconds => 'Skip back 10 seconds';

  @override
  String get playVideo => 'Play video';

  @override
  String get pauseVideo => 'Pause video';

  @override
  String get muteVideo => 'Mute video';

  @override
  String get unmuteVideo => 'Unmute video';

  @override
  String get skipForwardTenSeconds => 'Skip forward 10 seconds';

  @override
  String get enterFullscreen => 'Enter fullscreen';

  @override
  String get exitFullscreen => 'Exit fullscreen';

  @override
  String get loadedVideoReady => 'This video is ready for project setup.';

  @override
  String get selectingVideo => 'Selecting video...';

  @override
  String get replaceVideo => 'Replace video';

  @override
  String get checkSetup => 'Check setup';

  @override
  String get projectSetupComplete => 'Project setup is complete.';

  @override
  String get unableToUpdateSetup =>
      'Unable to update project setup. Please try again.';

  @override
  String get sourceRequired => 'Select a source video before processing.';

  @override
  String get targetLanguageRequired =>
      'Select a target language before processing.';

  @override
  String get mediaDetails => 'Media details';

  @override
  String get inspectMediaPrompt =>
      'Inspect this video to confirm its media details.';

  @override
  String get inspectVideo => 'Inspect video';

  @override
  String get inspectingMediaDetails => 'Inspecting media details...';

  @override
  String get duration => 'Duration';

  @override
  String get audio => 'Audio';

  @override
  String get audioPresent => 'Present';

  @override
  String get audioNotPresent => 'Not present';

  @override
  String get streams => 'Streams';

  @override
  String get unableToInspectMedia => 'Unable to inspect media';

  @override
  String get mediaErrorSourceNotFound =>
      'The selected video is no longer available. Choose it again.';

  @override
  String get mediaErrorSourceNotReadable =>
      'The selected video cannot be read. Check its permissions and choose it again.';

  @override
  String get mediaErrorUnsupported =>
      'This file is not a supported media format. Choose a different video.';

  @override
  String get mediaErrorMetadataUnavailable =>
      'Media details could not be read for this video. Choose a different video.';

  @override
  String get mediaErrorAudioMissing =>
      'This video has no audio stream and cannot be translated.';

  @override
  String get mediaErrorToolUnavailable =>
      'The media inspection tool is unavailable. Repair or reinstall the application.';

  @override
  String get mediaErrorUnknown =>
      'Media details could not be inspected. Please try again.';

  @override
  String get mediaStreamVideo => 'Video';

  @override
  String get mediaStreamAudio => 'Audio';

  @override
  String get mediaStreamSubtitle => 'Subtitle';

  @override
  String get mediaStreamData => 'Data';

  @override
  String get mediaStreamAttachment => 'Attachment';

  @override
  String get mediaStreamUnknown => 'Unknown';

  @override
  String engineStatus(Object status) {
    return 'Engine: $status';
  }

  @override
  String engineStatusSemantics(Object status) {
    return 'Engine status: $status';
  }

  @override
  String get engineStopped => 'Stopped';

  @override
  String get engineStarting => 'Starting';

  @override
  String get engineReady => 'Ready';

  @override
  String get engineUnavailable => 'Unavailable';

  @override
  String get engineCrashed => 'Crashed';

  @override
  String get changeAppLanguage => 'Change app language';

  @override
  String get workflowSelectionQuestion => 'What would you like to translate?';

  @override
  String get videoTranslationWorkflow => 'Video Translation';

  @override
  String get documentTranslationWorkflow => 'Document Translation';
}
