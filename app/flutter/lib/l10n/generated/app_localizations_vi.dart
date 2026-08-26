// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get languageEnglish => 'Tiếng Anh';

  @override
  String get languageVietnamese => 'Tiếng Việt';

  @override
  String get languageJapanese => 'Tiếng Nhật';

  @override
  String get languageKorean => 'Tiếng Hàn';

  @override
  String get languageChineseSimplified => 'Tiếng Trung (Giản thể)';

  @override
  String get languageChineseTraditional => 'Tiếng Trung (Phồn thể)';

  @override
  String get languagePortugueseBrazil => 'Tiếng Bồ Đào Nha (Brazil)';

  @override
  String get languagePortuguesePortugal => 'Tiếng Bồ Đào Nha (Bồ Đào Nha)';

  @override
  String get languageFrench => 'Tiếng Pháp';

  @override
  String get languageGerman => 'Tiếng Đức';

  @override
  String get languageSpanish => 'Tiếng Tây Ban Nha';

  @override
  String get languageItalian => 'Tiếng Ý';

  @override
  String get languageRussian => 'Tiếng Nga';

  @override
  String get languageHindi => 'Tiếng Hindi';

  @override
  String get languageArabic => 'Tiếng Ả Rập';

  @override
  String get languageThai => 'Tiếng Thái';

  @override
  String get languageIndonesian => 'Tiếng Indonesia';

  @override
  String get emptyWorkspaceTitle => 'Bắt đầu dự án dịch';

  @override
  String get emptyWorkspaceDescription =>
      'Mở video trên máy để kiểm tra thông tin media và chọn ngôn ngữ dịch.';

  @override
  String get openVideoEmptyState => 'Mở video';

  @override
  String get selectingVideoEmptyState => 'Đang chọn video...';

  @override
  String get appTitle => 'Trình dịch video';

  @override
  String get sourceLanguage => 'Ngôn ngữ nguồn';

  @override
  String get targetLanguage => 'Ngôn ngữ đích';

  @override
  String get automaticDetection => 'Tự động nhận diện';

  @override
  String get noTargetLanguageSelected => 'Chưa chọn ngôn ngữ đích';

  @override
  String get selectSourceLanguage => 'Chọn ngôn ngữ nguồn';

  @override
  String get selectTargetLanguage => 'Chọn ngôn ngữ đích';

  @override
  String get autoDetect => 'Tự động nhận diện';

  @override
  String get openingVideoPreview => 'Đang mở xem trước video...';

  @override
  String get videoPreviewUnavailable => 'Không thể xem trước video.';

  @override
  String get preparingVideoPreview => 'Đang chuẩn bị xem trước video...';

  @override
  String get skipBackTenSeconds => 'Lùi 10 giây';

  @override
  String get playVideo => 'Phát video';

  @override
  String get pauseVideo => 'Tạm dừng video';

  @override
  String get muteVideo => 'Tắt tiếng video';

  @override
  String get unmuteVideo => 'Bật tiếng video';

  @override
  String get skipForwardTenSeconds => 'Tiến 10 giây';

  @override
  String get enterFullscreen => 'Vào toàn màn hình';

  @override
  String get exitFullscreen => 'Thoát toàn màn hình';

  @override
  String get loadedVideoReady => 'Video này đã sẵn sàng để thiết lập dự án.';

  @override
  String get selectingVideo => 'Đang chọn video...';

  @override
  String get replaceVideo => 'Thay video';

  @override
  String get checkSetup => 'Kiểm tra thiết lập';

  @override
  String get projectSetupComplete => 'Thiết lập dự án đã hoàn tất.';

  @override
  String get unableToUpdateSetup =>
      'Không thể cập nhật thiết lập dự án. Vui lòng thử lại.';

  @override
  String get sourceRequired => 'Chọn video nguồn trước khi xử lý.';

  @override
  String get targetLanguageRequired => 'Chọn ngôn ngữ đích trước khi xử lý.';

  @override
  String get mediaDetails => 'Thông tin media';

  @override
  String get inspectMediaPrompt =>
      'Kiểm tra video này để xác nhận thông tin media.';

  @override
  String get inspectVideo => 'Kiểm tra video';

  @override
  String get inspectingMediaDetails => 'Đang kiểm tra thông tin media...';

  @override
  String get duration => 'Thời lượng';

  @override
  String get audio => 'Âm thanh';

  @override
  String get audioPresent => 'Có';

  @override
  String get audioNotPresent => 'Không có';

  @override
  String get streams => 'Luồng';

  @override
  String get unableToInspectMedia => 'Không thể kiểm tra media';

  @override
  String get mediaErrorSourceNotFound =>
      'Video đã chọn không còn khả dụng. Hãy chọn lại.';

  @override
  String get mediaErrorSourceNotReadable =>
      'Không thể đọc video đã chọn. Hãy kiểm tra quyền truy cập và chọn lại.';

  @override
  String get mediaErrorUnsupported =>
      'Tệp này không phải định dạng media được hỗ trợ. Hãy chọn video khác.';

  @override
  String get mediaErrorMetadataUnavailable =>
      'Không thể đọc thông tin media của video này. Hãy chọn video khác.';

  @override
  String get mediaErrorAudioMissing =>
      'Video này không có luồng âm thanh và không thể dịch.';

  @override
  String get mediaErrorToolUnavailable =>
      'Công cụ kiểm tra media không khả dụng. Hãy sửa chữa hoặc cài đặt lại ứng dụng.';

  @override
  String get mediaErrorUnknown =>
      'Không thể kiểm tra thông tin media. Vui lòng thử lại.';

  @override
  String get mediaStreamVideo => 'Video';

  @override
  String get mediaStreamAudio => 'Âm thanh';

  @override
  String get mediaStreamSubtitle => 'Phụ đề';

  @override
  String get mediaStreamData => 'Dữ liệu';

  @override
  String get mediaStreamAttachment => 'Tệp đính kèm';

  @override
  String get mediaStreamUnknown => 'Không rõ';

  @override
  String engineStatus(Object status) {
    return 'Bộ máy: $status';
  }

  @override
  String engineStatusSemantics(Object status) {
    return 'Trạng thái bộ máy: $status';
  }

  @override
  String get engineStopped => 'Đã dừng';

  @override
  String get engineStarting => 'Đang khởi động';

  @override
  String get engineReady => 'Sẵn sàng';

  @override
  String get engineUnavailable => 'Không khả dụng';

  @override
  String get engineCrashed => 'Đã gặp sự cố';

  @override
  String get changeAppLanguage => 'Đổi ngôn ngữ ứng dụng';

  @override
  String get workflowSelectionQuestion => 'Bạn muốn dịch nội dung gì?';

  @override
  String get videoTranslationWorkflow => 'Dịch video';

  @override
  String get documentTranslationWorkflow => 'Dịch tài liệu';

  @override
  String get documentLauncherDescription =>
      'Chọn EPUB, TXT hoặc PDF trên máy để xem chỉ đọc.';

  @override
  String get selectDocument => 'Chọn tài liệu';

  @override
  String get replaceDocument => 'Thay tài liệu';

  @override
  String get selectingDocument => 'Đang chọn tài liệu...';

  @override
  String documentSelected(Object fileName) {
    return 'Tài liệu đã chọn: $fileName';
  }

  @override
  String get documentSourceUnsupported =>
      'Tệp này không được hỗ trợ để xem tài liệu. Hãy chọn EPUB, TXT hoặc PDF.';

  @override
  String get documentSelectionFailed =>
      'Không thể chọn tài liệu. Vui lòng thử lại.';

  @override
  String get documentWorkspaceTitle => 'Xử lý tài liệu';

  @override
  String get documentSourceMissing => 'Chưa chọn tài liệu';

  @override
  String get replacingDocument => 'Đang thay tài liệu...';

  @override
  String get documentReaderUnavailableTitle => 'Chưa hỗ trợ loại file này';

  @override
  String get documentReaderUnavailableDescription =>
      'Trình đọc chỉ đọc theo từng định dạng sẽ được thêm trong tác vụ riêng.';

  @override
  String get epubReaderFileTooLarge =>
      'EPUB này lớn hơn giới hạn trình đọc 50 MiB.';

  @override
  String get plainTextReaderFileTooLarge =>
      'Tệp văn bản này lớn hơn giới hạn trình đọc 10 MiB.';

  @override
  String get plainTextReaderUnsupportedContent =>
      'Trình đọc này chỉ hỗ trợ văn bản UTF-8; không thể hiển thị nội dung nhị phân hoặc văn bản không hợp lệ.';

  @override
  String get pdfReaderFileTooLarge =>
      'PDF này vượt quá giới hạn trình đọc 50 MiB.';

  @override
  String get pdfReaderTooManyPages =>
      'PDF này có nhiều hơn giới hạn 500 trang.';

  @override
  String get pdfReaderPreviousPage => 'Trang trước';

  @override
  String get pdfReaderNextPage => 'Trang tiếp theo';

  @override
  String get pdfReaderZoomOut => 'Thu nhỏ';

  @override
  String get pdfReaderZoomIn => 'Phóng to';

  @override
  String pdfReaderPageStatus(Object current, Object total) {
    return 'Trang $current trên $total';
  }

  @override
  String get processingStatusTitle => 'Đang xử lý';

  @override
  String get processingPreparing => 'Đang chuẩn bị xử lý...';

  @override
  String get processingWorking => 'Đang xử lý...';

  @override
  String processingProgressUnits(Object completed, Object total) {
    return '$completed trên $total đơn vị';
  }

  @override
  String get cancelProcessing => 'Hủy';

  @override
  String get cancellationRequested => 'Đã yêu cầu hủy';

  @override
  String get processingCompleted => 'Đã xử lý xong.';

  @override
  String get processingFailed => 'Xử lý thất bại.';

  @override
  String get processingCancelled => 'Đã hủy xử lý.';

  @override
  String get processingRecoveryAvailable => 'Có thể phục hồi xử lý.';

  @override
  String get processingRecoveryFailed => 'Không thể phục hồi xử lý.';

  @override
  String get epubTranslationTitle => 'Dich EPUB';

  @override
  String get epubModelLabel => 'Mo hinh Ollama cuc bo';

  @override
  String get epubModelHint => 'Nhap ID mo hinh da cai dat';

  @override
  String get translateEpub => 'Dich EPUB';

  @override
  String get epubOriginal => 'Ban goc';

  @override
  String get epubTranslated => 'Ban dich';

  @override
  String get epubStageTranslating => 'Dang dich EPUB...';

  @override
  String get epubStageExporting => 'Dang kiem tra va xuat EPUB...';

  @override
  String get epubStageWorking => 'Dang xu ly EPUB...';

  @override
  String get epubStartFailed =>
      'Khong the bat dau dich EPUB. Hay kiem tra bo may va thu lai.';

  @override
  String get epubCancelFailed =>
      'Khong the yeu cau huy. Bo may co the van hoan tat cong viec.';

  @override
  String get epubLoadingOutput => 'Dang mo EPUB dich da duoc kiem tra...';

  @override
  String get epubOutputLoadFailed =>
      'EPUB da duoc xuat nhung khong the mo trong trinh doc nay.';
}
