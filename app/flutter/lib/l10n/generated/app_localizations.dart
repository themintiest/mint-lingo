import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_vi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('vi'),
  ];

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageVietnamese.
  ///
  /// In en, this message translates to:
  /// **'Vietnamese'**
  String get languageVietnamese;

  /// No description provided for @languageJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get languageJapanese;

  /// No description provided for @languageKorean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get languageKorean;

  /// No description provided for @languageChineseSimplified.
  ///
  /// In en, this message translates to:
  /// **'Chinese (Simplified)'**
  String get languageChineseSimplified;

  /// No description provided for @languageChineseTraditional.
  ///
  /// In en, this message translates to:
  /// **'Chinese (Traditional)'**
  String get languageChineseTraditional;

  /// No description provided for @languagePortugueseBrazil.
  ///
  /// In en, this message translates to:
  /// **'Portuguese (Brazil)'**
  String get languagePortugueseBrazil;

  /// No description provided for @languagePortuguesePortugal.
  ///
  /// In en, this message translates to:
  /// **'Portuguese (Portugal)'**
  String get languagePortuguesePortugal;

  /// No description provided for @languageFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get languageFrench;

  /// No description provided for @languageGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get languageGerman;

  /// No description provided for @languageSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get languageSpanish;

  /// No description provided for @languageItalian.
  ///
  /// In en, this message translates to:
  /// **'Italian'**
  String get languageItalian;

  /// No description provided for @languageRussian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get languageRussian;

  /// No description provided for @languageHindi.
  ///
  /// In en, this message translates to:
  /// **'Hindi'**
  String get languageHindi;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get languageArabic;

  /// No description provided for @languageThai.
  ///
  /// In en, this message translates to:
  /// **'Thai'**
  String get languageThai;

  /// No description provided for @languageIndonesian.
  ///
  /// In en, this message translates to:
  /// **'Indonesian'**
  String get languageIndonesian;

  /// No description provided for @emptyWorkspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Start a translation project'**
  String get emptyWorkspaceTitle;

  /// No description provided for @emptyWorkspaceDescription.
  ///
  /// In en, this message translates to:
  /// **'Open a local video to inspect its media and choose translation languages.'**
  String get emptyWorkspaceDescription;

  /// No description provided for @openVideoEmptyState.
  ///
  /// In en, this message translates to:
  /// **'Open a video'**
  String get openVideoEmptyState;

  /// No description provided for @selectingVideoEmptyState.
  ///
  /// In en, this message translates to:
  /// **'Selecting video...'**
  String get selectingVideoEmptyState;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Video Translator'**
  String get appTitle;

  /// No description provided for @sourceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Source language'**
  String get sourceLanguage;

  /// No description provided for @targetLanguage.
  ///
  /// In en, this message translates to:
  /// **'Target language'**
  String get targetLanguage;

  /// No description provided for @automaticDetection.
  ///
  /// In en, this message translates to:
  /// **'Automatic detection'**
  String get automaticDetection;

  /// No description provided for @noTargetLanguageSelected.
  ///
  /// In en, this message translates to:
  /// **'No target language selected'**
  String get noTargetLanguageSelected;

  /// No description provided for @selectSourceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select source language'**
  String get selectSourceLanguage;

  /// No description provided for @selectTargetLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select target language'**
  String get selectTargetLanguage;

  /// No description provided for @autoDetect.
  ///
  /// In en, this message translates to:
  /// **'Auto-detect'**
  String get autoDetect;

  /// No description provided for @openingVideoPreview.
  ///
  /// In en, this message translates to:
  /// **'Opening video preview...'**
  String get openingVideoPreview;

  /// No description provided for @videoPreviewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Video preview is unavailable.'**
  String get videoPreviewUnavailable;

  /// No description provided for @preparingVideoPreview.
  ///
  /// In en, this message translates to:
  /// **'Preparing video preview...'**
  String get preparingVideoPreview;

  /// No description provided for @skipBackTenSeconds.
  ///
  /// In en, this message translates to:
  /// **'Skip back 10 seconds'**
  String get skipBackTenSeconds;

  /// No description provided for @playVideo.
  ///
  /// In en, this message translates to:
  /// **'Play video'**
  String get playVideo;

  /// No description provided for @pauseVideo.
  ///
  /// In en, this message translates to:
  /// **'Pause video'**
  String get pauseVideo;

  /// No description provided for @muteVideo.
  ///
  /// In en, this message translates to:
  /// **'Mute video'**
  String get muteVideo;

  /// No description provided for @unmuteVideo.
  ///
  /// In en, this message translates to:
  /// **'Unmute video'**
  String get unmuteVideo;

  /// No description provided for @skipForwardTenSeconds.
  ///
  /// In en, this message translates to:
  /// **'Skip forward 10 seconds'**
  String get skipForwardTenSeconds;

  /// No description provided for @enterFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Enter fullscreen'**
  String get enterFullscreen;

  /// No description provided for @exitFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit fullscreen'**
  String get exitFullscreen;

  /// No description provided for @loadedVideoReady.
  ///
  /// In en, this message translates to:
  /// **'This video is ready for project setup.'**
  String get loadedVideoReady;

  /// No description provided for @selectingVideo.
  ///
  /// In en, this message translates to:
  /// **'Selecting video...'**
  String get selectingVideo;

  /// No description provided for @replaceVideo.
  ///
  /// In en, this message translates to:
  /// **'Replace video'**
  String get replaceVideo;

  /// No description provided for @checkSetup.
  ///
  /// In en, this message translates to:
  /// **'Check setup'**
  String get checkSetup;

  /// No description provided for @projectSetupComplete.
  ///
  /// In en, this message translates to:
  /// **'Project setup is complete.'**
  String get projectSetupComplete;

  /// No description provided for @unableToUpdateSetup.
  ///
  /// In en, this message translates to:
  /// **'Unable to update project setup. Please try again.'**
  String get unableToUpdateSetup;

  /// No description provided for @sourceRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a source video before processing.'**
  String get sourceRequired;

  /// No description provided for @targetLanguageRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a target language before processing.'**
  String get targetLanguageRequired;

  /// No description provided for @mediaDetails.
  ///
  /// In en, this message translates to:
  /// **'Media details'**
  String get mediaDetails;

  /// No description provided for @inspectMediaPrompt.
  ///
  /// In en, this message translates to:
  /// **'Inspect this video to confirm its media details.'**
  String get inspectMediaPrompt;

  /// No description provided for @inspectVideo.
  ///
  /// In en, this message translates to:
  /// **'Inspect video'**
  String get inspectVideo;

  /// No description provided for @inspectingMediaDetails.
  ///
  /// In en, this message translates to:
  /// **'Inspecting media details...'**
  String get inspectingMediaDetails;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @audio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audio;

  /// No description provided for @audioPresent.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get audioPresent;

  /// No description provided for @audioNotPresent.
  ///
  /// In en, this message translates to:
  /// **'Not present'**
  String get audioNotPresent;

  /// No description provided for @streams.
  ///
  /// In en, this message translates to:
  /// **'Streams'**
  String get streams;

  /// No description provided for @unableToInspectMedia.
  ///
  /// In en, this message translates to:
  /// **'Unable to inspect media'**
  String get unableToInspectMedia;

  /// No description provided for @mediaErrorSourceNotFound.
  ///
  /// In en, this message translates to:
  /// **'The selected video is no longer available. Choose it again.'**
  String get mediaErrorSourceNotFound;

  /// No description provided for @mediaErrorSourceNotReadable.
  ///
  /// In en, this message translates to:
  /// **'The selected video cannot be read. Check its permissions and choose it again.'**
  String get mediaErrorSourceNotReadable;

  /// No description provided for @mediaErrorUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This file is not a supported media format. Choose a different video.'**
  String get mediaErrorUnsupported;

  /// No description provided for @mediaErrorMetadataUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Media details could not be read for this video. Choose a different video.'**
  String get mediaErrorMetadataUnavailable;

  /// No description provided for @mediaErrorAudioMissing.
  ///
  /// In en, this message translates to:
  /// **'This video has no audio stream and cannot be translated.'**
  String get mediaErrorAudioMissing;

  /// No description provided for @mediaErrorToolUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The media inspection tool is unavailable. Repair or reinstall the application.'**
  String get mediaErrorToolUnavailable;

  /// No description provided for @mediaErrorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Media details could not be inspected. Please try again.'**
  String get mediaErrorUnknown;

  /// No description provided for @mediaStreamVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get mediaStreamVideo;

  /// No description provided for @mediaStreamAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get mediaStreamAudio;

  /// No description provided for @mediaStreamSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitle'**
  String get mediaStreamSubtitle;

  /// No description provided for @mediaStreamData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get mediaStreamData;

  /// No description provided for @mediaStreamAttachment.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get mediaStreamAttachment;

  /// No description provided for @mediaStreamUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get mediaStreamUnknown;

  /// No description provided for @engineStatus.
  ///
  /// In en, this message translates to:
  /// **'Engine: {status}'**
  String engineStatus(Object status);

  /// No description provided for @engineStatusSemantics.
  ///
  /// In en, this message translates to:
  /// **'Engine status: {status}'**
  String engineStatusSemantics(Object status);

  /// No description provided for @engineStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get engineStopped;

  /// No description provided for @engineStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get engineStarting;

  /// No description provided for @engineReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get engineReady;

  /// No description provided for @engineUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get engineUnavailable;

  /// No description provided for @engineCrashed.
  ///
  /// In en, this message translates to:
  /// **'Crashed'**
  String get engineCrashed;

  /// No description provided for @changeAppLanguage.
  ///
  /// In en, this message translates to:
  /// **'Change app language'**
  String get changeAppLanguage;

  /// No description provided for @workflowSelectionQuestion.
  ///
  /// In en, this message translates to:
  /// **'What would you like to translate?'**
  String get workflowSelectionQuestion;

  /// No description provided for @videoTranslationWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Video Translation'**
  String get videoTranslationWorkflow;

  /// No description provided for @documentTranslationWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Document Translation'**
  String get documentTranslationWorkflow;

  /// No description provided for @documentLauncherDescription.
  ///
  /// In en, this message translates to:
  /// **'Select a local EPUB, TXT, or PDF for read-only viewing.'**
  String get documentLauncherDescription;

  /// No description provided for @selectDocument.
  ///
  /// In en, this message translates to:
  /// **'Select document'**
  String get selectDocument;

  /// No description provided for @replaceDocument.
  ///
  /// In en, this message translates to:
  /// **'Replace document'**
  String get replaceDocument;

  /// No description provided for @selectingDocument.
  ///
  /// In en, this message translates to:
  /// **'Selecting document...'**
  String get selectingDocument;

  /// No description provided for @documentSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected document: {fileName}'**
  String documentSelected(Object fileName);

  /// No description provided for @documentSourceUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This file is not supported for document viewing. Choose an EPUB, TXT, or PDF.'**
  String get documentSourceUnsupported;

  /// No description provided for @documentSelectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to select the document. Please try again.'**
  String get documentSelectionFailed;

  /// No description provided for @documentWorkspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Document Workspace'**
  String get documentWorkspaceTitle;

  /// No description provided for @documentSourceMissing.
  ///
  /// In en, this message translates to:
  /// **'No document source is selected.'**
  String get documentSourceMissing;

  /// No description provided for @replacingDocument.
  ///
  /// In en, this message translates to:
  /// **'Replacing document...'**
  String get replacingDocument;

  /// No description provided for @documentReaderUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Reader surface not available yet'**
  String get documentReaderUnavailableTitle;

  /// No description provided for @documentReaderUnavailableDescription.
  ///
  /// In en, this message translates to:
  /// **'A format-specific read-only reader will be added in its own task.'**
  String get documentReaderUnavailableDescription;

  /// No description provided for @epubReaderFileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'This EPUB is larger than the 50 MiB reader limit.'**
  String get epubReaderFileTooLarge;

  /// No description provided for @plainTextReaderFileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'This text file is larger than the 10 MiB reader limit.'**
  String get plainTextReaderFileTooLarge;

  /// No description provided for @plainTextReaderUnsupportedContent.
  ///
  /// In en, this message translates to:
  /// **'This reader supports UTF-8 text only; binary or invalid text content cannot be displayed.'**
  String get plainTextReaderUnsupportedContent;

  /// No description provided for @pdfReaderFileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'This PDF is larger than the 50 MiB reader limit.'**
  String get pdfReaderFileTooLarge;

  /// No description provided for @pdfReaderTooManyPages.
  ///
  /// In en, this message translates to:
  /// **'This PDF has more than the 500-page reader limit.'**
  String get pdfReaderTooManyPages;

  /// No description provided for @pdfReaderPreviousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get pdfReaderPreviousPage;

  /// No description provided for @pdfReaderNextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get pdfReaderNextPage;

  /// No description provided for @pdfReaderZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get pdfReaderZoomOut;

  /// No description provided for @pdfReaderZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get pdfReaderZoomIn;

  /// No description provided for @pdfReaderPageStatus.
  ///
  /// In en, this message translates to:
  /// **'Page {current} of {total}'**
  String pdfReaderPageStatus(Object current, Object total);

  /// No description provided for @processingStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get processingStatusTitle;

  /// No description provided for @processingPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing processing...'**
  String get processingPreparing;

  /// No description provided for @processingWorking.
  ///
  /// In en, this message translates to:
  /// **'Working...'**
  String get processingWorking;

  /// No description provided for @processingProgressUnits.
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total} units'**
  String processingProgressUnits(Object completed, Object total);

  /// No description provided for @cancelProcessing.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelProcessing;

  /// No description provided for @cancellationRequested.
  ///
  /// In en, this message translates to:
  /// **'Cancellation requested'**
  String get cancellationRequested;

  /// No description provided for @processingCompleted.
  ///
  /// In en, this message translates to:
  /// **'Processing completed.'**
  String get processingCompleted;

  /// No description provided for @processingFailed.
  ///
  /// In en, this message translates to:
  /// **'Processing failed.'**
  String get processingFailed;

  /// No description provided for @processingCancelled.
  ///
  /// In en, this message translates to:
  /// **'Processing cancelled.'**
  String get processingCancelled;

  /// No description provided for @processingRecoveryAvailable.
  ///
  /// In en, this message translates to:
  /// **'Processing can be recovered.'**
  String get processingRecoveryAvailable;

  /// No description provided for @processingRecoveryFailed.
  ///
  /// In en, this message translates to:
  /// **'Processing could not be recovered.'**
  String get processingRecoveryFailed;

  /// No description provided for @epubTranslationTitle.
  ///
  /// In en, this message translates to:
  /// **'Translate EPUB'**
  String get epubTranslationTitle;

  /// No description provided for @epubModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Installed Ollama model'**
  String get epubModelLabel;

  /// No description provided for @epubModelHint.
  ///
  /// In en, this message translates to:
  /// **'Choose an installed model'**
  String get epubModelHint;

  /// No description provided for @epubModelLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading installed Ollama models…'**
  String get epubModelLoading;

  /// No description provided for @epubModelEmpty.
  ///
  /// In en, this message translates to:
  /// **'No installed Ollama translation models are available. Install a completion-capable model, then refresh.'**
  String get epubModelEmpty;

  /// No description provided for @epubModelUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Ollama models could not be loaded. Start Ollama, then refresh.'**
  String get epubModelUnavailable;

  /// No description provided for @epubModelRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh models'**
  String get epubModelRefresh;

  /// No description provided for @translateEpub.
  ///
  /// In en, this message translates to:
  /// **'Translate EPUB'**
  String get translateEpub;

  /// No description provided for @epubOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get epubOriginal;

  /// No description provided for @epubTranslated.
  ///
  /// In en, this message translates to:
  /// **'Translated'**
  String get epubTranslated;

  /// No description provided for @epubStageTranslating.
  ///
  /// In en, this message translates to:
  /// **'Translating EPUB...'**
  String get epubStageTranslating;

  /// No description provided for @epubStageExporting.
  ///
  /// In en, this message translates to:
  /// **'Validating and exporting EPUB...'**
  String get epubStageExporting;

  /// No description provided for @epubStageWorking.
  ///
  /// In en, this message translates to:
  /// **'Processing EPUB...'**
  String get epubStageWorking;

  /// No description provided for @epubStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to start EPUB translation. Check the engine and try again.'**
  String get epubStartFailed;

  /// No description provided for @epubCancelFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to request cancellation. The engine may still finish the job.'**
  String get epubCancelFailed;

  /// No description provided for @epubLoadingOutput.
  ///
  /// In en, this message translates to:
  /// **'Opening the validated translated EPUB...'**
  String get epubLoadingOutput;

  /// No description provided for @epubOutputLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'The EPUB was exported but could not be opened in this reader.'**
  String get epubOutputLoadFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'vi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'vi':
      return AppLocalizationsVi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
