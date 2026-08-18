import json
import subprocess
import sys
import unittest
from datetime import timedelta
from pathlib import Path

from video_translator_engine.media import (
    MediaDimensions,
    MediaMetadata,
    MediaStream,
    MediaStreamKind,
    MediaValidationError,
    MediaValidationErrorCode,
)
from video_translator_engine.media_validation import (
    MediaValidationFailure,
    MediaValidationSuccess,
)
from video_translator_engine.worker import handle_message


class WorkerProtocolTest(unittest.TestCase):
    def setUp(self) -> None:
        self.process = subprocess.Popen(
            [sys.executable, "-m", "video_translator_engine.worker"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertIsNotNone(self.process.stdin)
        self.assertIsNotNone(self.process.stdout)

    def tearDown(self) -> None:
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait(timeout=5)
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            if stream is not None and not stream.closed:
                stream.close()

    def _send(self, message: dict[str, object]) -> None:
        assert self.process.stdin is not None
        self.process.stdin.write(json.dumps(message))
        self.process.stdin.write("\n")
        self.process.stdin.flush()

    def _receive(self) -> dict[str, object]:
        assert self.process.stdout is not None
        line = self.process.stdout.readline()
        self.assertNotEqual(line, "")
        return json.loads(line)

    def test_get_info_then_shutdown_uses_only_json_on_stdout(self) -> None:
        self._send(
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "get-info-001",
                "method": "engine.getInfo",
            }
        )
        self.assertEqual(
            self._receive(),
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "get-info-001",
                "result": {
                    "engineVersion": "0.1.0",
                    "protocolVersion": "1.0",
                },
            },
        )

        self._send(
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "shutdown-001",
                "method": "engine.shutdown",
            }
        )
        self.assertEqual(self._receive()["result"], {"accepted": True})
        self.assertEqual(self.process.wait(timeout=5), 0)

    def test_handles_partial_multiple_blank_and_malformed_frames(self) -> None:
        assert self.process.stdin is not None
        self.process.stdin.write('{"jsonrpc":"2.0","protocolVersion":"1.0",')
        self.process.stdin.flush()
        self.process.stdin.write(
            '"id":"first","method":"engine.getInfo"}\n\n'
            '{"jsonrpc":"2.0","protocolVersion":"1.0","id":"second",'
            '"method":"engine.getInfo"}\nnot json\n'
        )
        self.process.stdin.flush()

        self.assertEqual(self._receive()["id"], "first")
        self.assertEqual(self._receive()["id"], "second")
        malformed = self._receive()
        self.assertEqual(malformed["id"], None)
        self.assertEqual(malformed["error"]["code"], -32700)

    def test_returns_structured_errors(self) -> None:
        self._send(
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "unknown-001",
                "method": "unknown.method",
            }
        )
        unknown_method = self._receive()
        self.assertEqual(unknown_method["error"]["code"], -32601)
        self.assertEqual(
            unknown_method["error"]["data"]["engineCode"],
            "engine.method_not_found",
        )

        self._send(
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "invalid-params-001",
                "method": "engine.getInfo",
                "params": {},
            }
        )
        invalid_params = self._receive()
        self.assertEqual(invalid_params["error"]["code"], -32602)
        self.assertEqual(
            invalid_params["error"]["data"]["engineCode"],
            "engine.invalid_params",
        )


class MediaInspectionWorkerTest(unittest.TestCase):
    def test_returns_shared_success_shape_for_validated_metadata(self) -> None:
        validator = _FakeMediaValidator(
            MediaValidationSuccess(
                MediaMetadata(
                    duration=timedelta(seconds=95.5),
                    streams=(
                        MediaStream(
                            index=0,
                            kind=MediaStreamKind.VIDEO,
                            codec="h264",
                            dimensions=MediaDimensions(width=1920, height=1080),
                        ),
                        MediaStream(
                            index=1,
                            kind=MediaStreamKind.AUDIO,
                            codec="aac",
                        ),
                    ),
                )
            )
        )

        response, should_shutdown = handle_message(
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "media-inspect-001",
                "method": "media.inspect",
                "params": {"sourcePath": r"C:\videos\source.mp4"},
            },
            media_validator=validator,  # type: ignore[arg-type]
        )

        self.assertFalse(should_shutdown)
        self.assertEqual(
            response,
            _media_fixture("media-inspect-success-response.json"),
        )
        self.assertEqual(validator.sources, [Path(r"C:\videos\source.mp4")])

    def test_returns_shared_validation_error_without_echoing_the_source_path(self) -> None:
        validator = _FakeMediaValidator(
            MediaValidationFailure(
                MediaValidationError(
                    code=MediaValidationErrorCode.AUDIO_STREAM_MISSING,
                    message="The source media does not contain an audio stream.",
                )
            )
        )

        response, _ = handle_message(
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "media-inspect-001",
                "method": "media.inspect",
                "params": {"sourcePath": r"C:\private\source.mp4"},
            },
            media_validator=validator,  # type: ignore[arg-type]
        )

        self.assertEqual(response, _media_fixture("media-inspect-no-audio-error.json"))
        self.assertNotIn("C:\\private\\source.mp4", json.dumps(response))

    def test_rejects_params_that_include_media_content(self) -> None:
        response, _ = handle_message(_media_fixture("media-inspect-with-bytes.json"))

        self.assertEqual(response["error"]["code"], -32602)


class _FakeMediaValidator:
    def __init__(self, result: MediaValidationSuccess | MediaValidationFailure) -> None:
        self._result = result
        self.sources: list[Path] = []

    def validate(self, source: Path) -> MediaValidationSuccess | MediaValidationFailure:
        self.sources.append(source)
        return self._result


def _media_fixture(name: str) -> dict[str, object]:
    return json.loads(
        (
            Path(__file__).parents[3]
            / "shared"
            / "schemas"
            / "ipc"
            / "v1"
            / "fixtures"
            / "media"
            / ("invalid" if name == "media-inspect-with-bytes.json" else "valid")
            / name
        ).read_text(encoding="utf-8")
    )
