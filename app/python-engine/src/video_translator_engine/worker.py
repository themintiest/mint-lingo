"""JSON-RPC worker for engine lifecycle and media-inspection messages."""

from __future__ import annotations

import json
import logging
import sys
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import timedelta
from pathlib import Path
from typing import Any, BinaryIO

from video_translator_engine import __version__
from video_translator_engine.media import MediaMetadata, MediaValidationError
from video_translator_engine.media_probe import (
    FfprobeExecutableResolver,
    FfprobeResolutionFailure,
    MediaProbe,
    MediaToolResolutionMode,
    SubprocessFfprobeProcessRunner,
)
from video_translator_engine.media_validation import (
    MediaValidationFailure,
    SourceMediaValidator,
)


PROTOCOL_VERSION = "1.0"
MAX_FRAME_BYTES = 1_048_576


@dataclass(frozen=True)
class MalformedFrame:
    """A frame that cannot safely be dispatched."""

    reason: str


def iter_frames(stream: BinaryIO) -> Iterator[str | MalformedFrame]:
    """Yield complete UTF-8 NDJSON frames while enforcing the shared framing rules."""

    frame = bytearray()
    discarding = False

    while chunk := stream.read1(4_096):
        for byte in chunk:
            if byte == 0x0A:
                if discarding:
                    discarding = False
                    frame.clear()
                    yield MalformedFrame("frame_too_large")
                    continue

                if frame.endswith(b"\r"):
                    frame.pop()

                if not frame:
                    continue

                try:
                    yield frame.decode("utf-8")
                except UnicodeDecodeError:
                    yield MalformedFrame("invalid_utf8")
                finally:
                    frame.clear()
                continue

            if discarding:
                continue

            frame.append(byte)
            if len(frame) > MAX_FRAME_BYTES:
                discarding = True
                frame.clear()

    if discarding or frame:
        yield MalformedFrame("unterminated_frame")


def _is_request_id(value: object) -> bool:
    return (isinstance(value, str) and bool(value)) or (
        isinstance(value, int) and not isinstance(value, bool)
    )


def _recover_request_id(message: object) -> str | int | None:
    if isinstance(message, dict) and _is_request_id(message.get("id")):
        return message["id"]
    return None


def _error_response(
    request_id: str | int | None,
    *,
    code: int,
    message: str,
    engine_code: str,
    reason: str,
) -> dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "protocolVersion": PROTOCOL_VERSION,
        "id": request_id,
        "error": {
            "code": code,
            "message": message,
            "data": {
                "engineCode": engine_code,
                "safeDetails": {
                    "reason": reason,
                    "retryable": False,
                },
            },
        },
    }


def _success_response(request_id: str | int, result: dict[str, Any]) -> dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "protocolVersion": PROTOCOL_VERSION,
        "id": request_id,
        "result": result,
    }


def _media_validation_error_response(
    request_id: str | int,
    error: MediaValidationError,
) -> dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "protocolVersion": PROTOCOL_VERSION,
        "id": request_id,
        "error": {
            "code": -32010,
            "message": error.message,
            "data": {"mediaCode": error.code.value, "retryable": error.retryable},
        },
    }


def _media_tool_error_response(
    request_id: str | int,
    resolution: FfprobeResolutionFailure,
) -> dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "protocolVersion": PROTOCOL_VERSION,
        "id": request_id,
        "error": {
            "code": -32011,
            "message": "Media inspection tool is unavailable.",
            "data": {"toolCode": resolution.code.value, "retryable": False},
        },
    }


def _invalid_request(
    message: object,
    *,
    reason: str,
) -> tuple[dict[str, Any], bool]:
    return (
        _error_response(
            _recover_request_id(message),
            code=-32600,
            message="Invalid Request",
            engine_code="engine.invalid_request",
            reason=reason,
        ),
        False,
    )


def handle_message(
    message: object,
    *,
    media_validator: SourceMediaValidator | None = None,
) -> tuple[dict[str, Any] | None, bool]:
    """Handle one decoded JSON value and return an optional response and shutdown flag."""

    if not isinstance(message, dict):
        return _invalid_request(message, reason="invalid_envelope")

    allowed_members = {"jsonrpc", "protocolVersion", "id", "method", "params"}
    if set(message) - allowed_members:
        return _invalid_request(message, reason="invalid_envelope")

    if message.get("jsonrpc") != "2.0":
        return _invalid_request(message, reason="invalid_envelope")

    if message.get("protocolVersion") != PROTOCOL_VERSION:
        return _invalid_request(message, reason="unsupported_protocol_version")

    method = message.get("method")
    if not isinstance(method, str) or not method:
        return _invalid_request(message, reason="invalid_envelope")

    if "params" in message and not isinstance(message["params"], (dict, list)):
        return _invalid_request(message, reason="invalid_envelope")

    is_notification = "id" not in message
    if not is_notification and not _is_request_id(message["id"]):
        return _invalid_request(message, reason="invalid_envelope")

    if method == "media.inspect":
        if not _is_media_inspect_params(message.get("params")):
            response = _error_response(
                _recover_request_id(message),
                code=-32602,
                message="Invalid params",
                engine_code="engine.invalid_params",
                reason="invalid_parameters",
            )
            return (None if is_notification else response, False)
        if is_notification:
            return (None, False)

        validator = media_validator
        if validator is None:
            validator_or_failure = _default_media_validator()
            if isinstance(validator_or_failure, FfprobeResolutionFailure):
                return (_media_tool_error_response(message["id"], validator_or_failure), False)
            validator = validator_or_failure

        result = validator.validate(Path(message["params"]["sourcePath"]))
        if isinstance(result, MediaValidationFailure):
            return (_media_validation_error_response(message["id"], result.error), False)
        return (
            _success_response(message["id"], {"metadata": _metadata_to_json(result.metadata)}),
            False,
        )

    if "params" in message:
        response = _error_response(
            _recover_request_id(message),
            code=-32602,
            message="Invalid params",
            engine_code="engine.invalid_params",
            reason="invalid_parameters",
        )
        return (None if is_notification else response, False)

    if method == "engine.getInfo":
        if is_notification:
            return (None, False)
        response = _success_response(
            message["id"],
            {
                "engineVersion": __version__,
                "protocolVersion": PROTOCOL_VERSION,
            },
        )
        return (None if is_notification else response, False)

    if method == "engine.shutdown":
        if is_notification:
            return (None, True)
        response = _success_response(message["id"], {"accepted": True})
        return (response, True)

    response = _error_response(
        _recover_request_id(message),
        code=-32601,
        message="Method not found",
        engine_code="engine.method_not_found",
        reason="unsupported_method",
    )
    return (None if is_notification else response, False)


def _is_media_inspect_params(value: object) -> bool:
    if not isinstance(value, dict) or set(value) != {"sourcePath"}:
        return False
    source_path = value["sourcePath"]
    return (
        isinstance(source_path, str)
        and bool(source_path)
        and source_path.strip() == source_path
    )


def _default_media_validator() -> SourceMediaValidator | FfprobeResolutionFailure:
    resolution = FfprobeExecutableResolver(
        mode=MediaToolResolutionMode.DEVELOPMENT
    ).resolve()
    if isinstance(resolution, FfprobeResolutionFailure):
        return resolution
    return SourceMediaValidator(
        MediaProbe(resolution, SubprocessFfprobeProcessRunner())
    )


def _metadata_to_json(metadata: MediaMetadata) -> dict[str, Any]:
    return {
        "durationMicroseconds": metadata.duration // timedelta(microseconds=1),
        "streams": [
            {
                "index": stream.index,
                "kind": stream.kind.value,
                "codec": stream.codec,
                **(
                    {
                        "dimensions": {
                            "width": stream.dimensions.width,
                            "height": stream.dimensions.height,
                        }
                    }
                    if stream.dimensions is not None
                    else {}
                ),
            }
            for stream in metadata.streams
        ],
        "hasAudio": metadata.has_audio,
    }


def write_message(stream: Any, message: dict[str, Any]) -> None:
    """Write one compact UTF-8 JSON-RPC frame to stdout."""

    stream.write(json.dumps(message, ensure_ascii=False, separators=(",", ":")))
    stream.write("\n")
    stream.flush()


def main() -> int:
    """Run the worker without loading AI providers or models."""

    logging.basicConfig(level=logging.WARNING, stream=sys.stderr)

    for frame in iter_frames(sys.stdin.buffer):
        if isinstance(frame, MalformedFrame):
            write_message(
                sys.stdout,
                _error_response(
                    None,
                    code=-32700,
                    message="Parse error",
                    engine_code="engine.parse_error",
                    reason="malformed_json",
                ),
            )
            continue

        try:
            decoded = json.loads(frame)
        except json.JSONDecodeError:
            write_message(
                sys.stdout,
                _error_response(
                    None,
                    code=-32700,
                    message="Parse error",
                    engine_code="engine.parse_error",
                    reason="malformed_json",
                ),
            )
            continue

        try:
            response, should_shutdown = handle_message(decoded)
        except Exception:
            logging.exception("Unexpected inert worker failure")
            response = _error_response(
                _recover_request_id(decoded),
                code=-32603,
                message="Internal error",
                engine_code="engine.internal_error",
                reason="unexpected_failure",
            )
            should_shutdown = False

        if response is not None:
            write_message(sys.stdout, response)
        if should_shutdown:
            return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
