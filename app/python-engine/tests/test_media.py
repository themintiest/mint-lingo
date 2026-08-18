from dataclasses import FrozenInstanceError
from datetime import timedelta
import unittest

from video_translator_engine.media import (
    MediaDimensions,
    MediaMetadata,
    MediaStream,
    MediaStreamKind,
    MediaValidationError,
    MediaValidationErrorCode,
)


class MediaMetadataTest(unittest.TestCase):
    def test_normalizes_duration_streams_dimensions_codecs_and_audio_presence(self) -> None:
        metadata = MediaMetadata(
            duration=timedelta(seconds=95.5),
            streams=[
                MediaStream(
                    index=0,
                    kind=MediaStreamKind.VIDEO,
                    codec="H264",
                    dimensions=MediaDimensions(width=1920, height=1080),
                ),
                MediaStream(index=1, kind=MediaStreamKind.AUDIO, codec="AAC"),
                MediaStream(index=2, kind=MediaStreamKind.SUBTITLE, codec="SubRip"),
            ],
        )

        self.assertEqual(metadata.duration, timedelta(seconds=95.5))
        self.assertEqual(metadata.streams[0].codec, "h264")
        self.assertEqual(metadata.streams[0].dimensions, MediaDimensions(1920, 1080))
        self.assertEqual(metadata.audio_streams, (metadata.streams[1],))
        self.assertEqual(metadata.video_streams, (metadata.streams[0],))
        self.assertTrue(metadata.has_audio)
        self.assertIsInstance(metadata.streams, tuple)
        with self.assertRaises(FrozenInstanceError):
            metadata.duration = timedelta(seconds=1)  # type: ignore[misc]

    def test_reports_media_without_an_audio_stream(self) -> None:
        metadata = MediaMetadata(
            duration=timedelta(0),
            streams=(
                MediaStream(
                    index=0,
                    kind=MediaStreamKind.VIDEO,
                    codec="vp9",
                    dimensions=MediaDimensions(width=640, height=360),
                ),
            ),
        )

        self.assertEqual(metadata.audio_streams, ())
        self.assertFalse(metadata.has_audio)

    def test_rejects_inconsistent_or_invalid_metadata(self) -> None:
        with self.assertRaisesRegex(ValueError, "video streams require dimensions"):
            MediaStream(index=0, kind=MediaStreamKind.VIDEO, codec="h264")

        with self.assertRaisesRegex(ValueError, "only video streams can have dimensions"):
            MediaStream(
                index=1,
                kind=MediaStreamKind.AUDIO,
                codec="aac",
                dimensions=MediaDimensions(width=1, height=1),
            )

        stream = MediaStream(index=0, kind=MediaStreamKind.AUDIO, codec="aac")
        with self.assertRaisesRegex(ValueError, "stream indexes must be unique"):
            MediaMetadata(duration=timedelta(seconds=1), streams=(stream, stream))


class MediaValidationErrorTest(unittest.TestCase):
    def test_exposes_stable_structured_validation_errors(self) -> None:
        error = MediaValidationError(
            code=MediaValidationErrorCode.AUDIO_STREAM_MISSING,
            message="The source media does not contain an audio stream.",
        )

        self.assertEqual(error.code.value, "media.audio_stream_missing")
        self.assertEqual(
            error.message,
            "The source media does not contain an audio stream.",
        )
        self.assertFalse(error.retryable)
        with self.assertRaises(FrozenInstanceError):
            error.message = "A different message."  # type: ignore[misc]

    def test_rejects_unstructured_validation_error_values(self) -> None:
        with self.assertRaisesRegex(TypeError, "code must be a MediaValidationErrorCode"):
            MediaValidationError(  # type: ignore[arg-type]
                code="media.audio_stream_missing",
                message="Missing audio.",
            )
        with self.assertRaisesRegex(ValueError, "message must not be blank or padded"):
            MediaValidationError(
                code=MediaValidationErrorCode.SOURCE_NOT_FOUND,
                message=" Missing source.",
            )
