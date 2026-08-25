from datetime import timedelta
from pathlib import Path
import unittest

from mint_lingo_engine.media.models import MediaDimensions, MediaStreamKind
from mint_lingo_engine.media.probe import (
    FfprobeMetadataParseError,
    parse_ffprobe_metadata,
)


class FfprobeMetadataParserTest(unittest.TestCase):
    def test_parses_the_valid_video_and_audio_fixture(self) -> None:
        output = _fixture_path("video-with-audio.json").read_text(encoding="utf-8")

        metadata = parse_ffprobe_metadata(output)

        self.assertEqual(metadata.duration, timedelta(seconds=95.5))
        self.assertEqual(len(metadata.streams), 3)
        self.assertEqual(metadata.streams[0].kind, MediaStreamKind.VIDEO)
        self.assertEqual(metadata.streams[0].codec, "h264")
        self.assertEqual(metadata.streams[0].dimensions, MediaDimensions(1920, 1080))
        self.assertEqual(metadata.streams[1].kind, MediaStreamKind.AUDIO)
        self.assertEqual(metadata.streams[1].codec, "aac")
        self.assertTrue(metadata.has_audio)

    def test_normalizes_unrecognized_stream_types_without_losing_the_codec(self) -> None:
        metadata = parse_ffprobe_metadata(
            """
            {
              "format": {"duration": "0.000000"},
              "streams": [
                {"index": 0, "codec_name": "timed_id3", "codec_type": "metadata"}
              ]
            }
            """
        )

        self.assertEqual(metadata.streams[0].kind, MediaStreamKind.UNKNOWN)
        self.assertEqual(metadata.streams[0].codec, "timed_id3")
        self.assertFalse(metadata.has_audio)

    def test_rejects_invalid_json_and_incomplete_video_metadata(self) -> None:
        with self.assertRaisesRegex(FfprobeMetadataParseError, "not valid JSON"):
            parse_ffprobe_metadata("not JSON")

        with self.assertRaisesRegex(FfprobeMetadataParseError, "invalid shape"):
            parse_ffprobe_metadata(
                """
                {
                  "format": {"duration": "1"},
                  "streams": [
                    {"index": 0, "codec_name": "h264", "codec_type": "video"}
                  ]
                }
                """
            )


def _fixture_path(name: str) -> Path:
    return Path(__file__).parent / "fixtures" / "media" / "ffprobe" / "valid" / name
