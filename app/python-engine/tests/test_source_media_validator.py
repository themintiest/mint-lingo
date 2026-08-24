from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from mint_lingo_engine.media import MediaValidationErrorCode
from mint_lingo_engine.media_probe import FfprobeProcessResult
from mint_lingo_engine.media_validation import (
    MediaValidationFailure,
    MediaValidationSuccess,
    SourceMediaValidator,
)


class SourceMediaValidatorTest(unittest.TestCase):
    def test_missing_source_returns_a_structured_error_without_probing(self) -> None:
        probe = _FakeMediaProbe(_successful_probe_output())
        with TemporaryDirectory() as temporary_directory:
            result = SourceMediaValidator(probe).validate(
                Path(temporary_directory) / "missing.mp4"
            )

        self._assert_failure(result, MediaValidationErrorCode.SOURCE_NOT_FOUND)
        self.assertEqual(probe.sources, [])

    def test_unreadable_source_returns_a_structured_error_without_probing(self) -> None:
        source = self._create_source_file()
        probe = _FakeMediaProbe(_successful_probe_output())

        result = SourceMediaValidator(
            probe,
            is_readable=lambda path: False,
        ).validate(source)

        self._assert_failure(result, MediaValidationErrorCode.SOURCE_NOT_READABLE)
        self.assertEqual(probe.sources, [])

    def test_probe_rejection_maps_to_unsupported_media(self) -> None:
        source = self._create_source_file()
        result = SourceMediaValidator(
            _FakeMediaProbe("", return_code=1),
        ).validate(source)

        self._assert_failure(result, MediaValidationErrorCode.UNSUPPORTED_MEDIA)

    def test_invalid_probe_output_maps_to_unavailable_metadata(self) -> None:
        source = self._create_source_file()
        result = SourceMediaValidator(_FakeMediaProbe("not JSON")).validate(source)

        self._assert_failure(result, MediaValidationErrorCode.METADATA_UNAVAILABLE)

    def test_video_without_audio_maps_to_structured_audio_error(self) -> None:
        source = self._create_source_file()
        result = SourceMediaValidator(_FakeMediaProbe(_video_only_probe_output())).validate(
            source
        )

        self._assert_failure(result, MediaValidationErrorCode.AUDIO_STREAM_MISSING)

    def test_valid_source_returns_normalized_metadata(self) -> None:
        source = self._create_source_file()
        result = SourceMediaValidator(_FakeMediaProbe(_successful_probe_output())).validate(
            source
        )

        self.assertIsInstance(result, MediaValidationSuccess)
        assert isinstance(result, MediaValidationSuccess)
        self.assertTrue(result.metadata.has_audio)
        self.assertEqual(result.metadata.duration.total_seconds(), 5)

    def _create_source_file(self) -> Path:
        temporary_directory = self.enterContext(TemporaryDirectory())
        source = Path(temporary_directory) / "source.mp4"
        source.write_bytes(b"not real media")
        return source

    def _assert_failure(
        self,
        result: MediaValidationSuccess | MediaValidationFailure,
        code: MediaValidationErrorCode,
    ) -> None:
        self.assertIsInstance(result, MediaValidationFailure)
        assert isinstance(result, MediaValidationFailure)
        self.assertEqual(result.error.code, code)


class _FakeMediaProbe:
    def __init__(self, stdout: str, *, return_code: int = 0) -> None:
        self._result = FfprobeProcessResult(return_code, stdout, "")
        self.sources: list[Path] = []

    def inspect(self, source: Path) -> FfprobeProcessResult:
        self.sources.append(source)
        return self._result


def _successful_probe_output() -> str:
    return """
    {
      "format": {"duration": "5.000000"},
      "streams": [
        {
          "index": 0,
          "codec_name": "h264",
          "codec_type": "video",
          "width": 1920,
          "height": 1080
        },
        {"index": 1, "codec_name": "aac", "codec_type": "audio"}
      ]
    }
    """


def _video_only_probe_output() -> str:
    return """
    {
      "format": {"duration": "5.000000"},
      "streams": [
        {
          "index": 0,
          "codec_name": "h264",
          "codec_type": "video",
          "width": 1920,
          "height": 1080
        }
      ]
    }
    """
