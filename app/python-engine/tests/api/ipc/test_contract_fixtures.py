import json
import unittest
from pathlib import Path
from typing import Any


CONTRACT_ROOT = Path(__file__).parents[5] / "shared" / "schemas" / "ipc" / "v1"


def _is_request_id(value: Any) -> bool:
    return (isinstance(value, str) and bool(value)) or (
        isinstance(value, int) and not isinstance(value, bool)
    )


def _is_envelope(value: Any) -> bool:
    if not isinstance(value, dict):
        return False
    if value.get("jsonrpc") != "2.0" or value.get("protocolVersion") != "1.0":
        return False

    keys = set(value)
    if "method" in value:
        if not isinstance(value["method"], str) or not value["method"]:
            return False
        if "params" in value and not isinstance(value["params"], (dict, list)):
            return False
        allowed = {"jsonrpc", "protocolVersion", "method", "params"}
        if "id" not in value:
            return keys <= allowed
        return _is_request_id(value["id"]) and keys <= allowed | {"id"}

    if "result" in value:
        return (
            _is_request_id(value.get("id"))
            and keys <= {"jsonrpc", "protocolVersion", "id", "result"}
        )

    error = value.get("error")
    return (
        "id" in value
        and (value["id"] is None or _is_request_id(value["id"]))
        and isinstance(error, dict)
        and isinstance(error.get("code"), int)
        and not isinstance(error.get("code"), bool)
        and isinstance(error.get("message"), str)
        and bool(error["message"])
        and set(error) <= {"code", "message", "data"}
        and keys <= {"jsonrpc", "protocolVersion", "id", "error"}
    )


def _is_lifecycle_message(value: Any) -> bool:
    if not _is_envelope(value) or not isinstance(value, dict):
        return False
    if value.get("method") in {"engine.getInfo", "engine.shutdown"}:
        return "params" not in value
    result = value.get("result")
    if not isinstance(result, dict):
        return False
    return result in (
        {"engineVersion": "0.1.0", "protocolVersion": "1.0"},
        {"accepted": True},
    )


def _is_engine_error_data(value: Any) -> bool:
    return (
        isinstance(value, dict)
        and set(value) == {"engineCode", "safeDetails"}
        and value["engineCode"]
        in {
            "engine.parse_error",
            "engine.invalid_request",
            "engine.method_not_found",
            "engine.invalid_params",
            "engine.internal_error",
        }
        and isinstance(value["safeDetails"], dict)
        and set(value["safeDetails"]) == {"reason", "retryable"}
        and isinstance(value["safeDetails"]["retryable"], bool)
    )


def _is_media_inspection_message(value: Any) -> bool:
    if not _is_envelope(value) or not isinstance(value, dict):
        return False
    if value.get("method") == "media.inspect":
        params = value.get("params")
        return (
            isinstance(params, dict)
            and set(params) == {"sourcePath"}
            and isinstance(params["sourcePath"], str)
            and bool(params["sourcePath"])
        )

    result = value.get("result")
    if isinstance(result, dict):
        metadata = result.get("metadata")
        return (
            set(result) == {"metadata"}
            and isinstance(metadata, dict)
            and set(metadata) == {"durationMicroseconds", "streams", "hasAudio"}
            and isinstance(metadata["durationMicroseconds"], int)
            and not isinstance(metadata["durationMicroseconds"], bool)
            and metadata["durationMicroseconds"] >= 0
            and isinstance(metadata["streams"], list)
            and bool(metadata["streams"])
            and isinstance(metadata["hasAudio"], bool)
        )

    error = value.get("error")
    if not isinstance(error, dict) or not isinstance(error.get("data"), dict):
        return False
    data = error["data"]
    if error.get("code") == -32010:
        return (
            set(data) == {"mediaCode", "retryable"}
            and data["mediaCode"]
            in {
                "media.source_not_found",
                "media.source_not_readable",
                "media.unsupported_media",
                "media.metadata_unavailable",
                "media.audio_stream_missing",
            }
            and isinstance(data["retryable"], bool)
        )
    return (
        error.get("code") == -32011
        and error.get("message") == "Media inspection tool is unavailable."
        and set(data) == {"toolCode", "retryable"}
        and data["toolCode"]
        in {"media.ffprobe_unsupported_platform", "media.ffprobe_unavailable"}
        and data["retryable"] is False
    )


class IpcContractFixtureTest(unittest.TestCase):
    def test_generic_envelope_fixtures(self) -> None:
        for expected, directory in (
            (True, CONTRACT_ROOT / "fixtures" / "valid"),
            (False, CONTRACT_ROOT / "fixtures" / "invalid"),
        ):
            for fixture in directory.glob("*.json"):
                with self.subTest(fixture=fixture.name):
                    value = json.loads(fixture.read_text(encoding="utf-8"))
                    self.assertIs(_is_envelope(value), expected)

    def test_engine_lifecycle_and_error_fixtures(self) -> None:
        valid_directory = CONTRACT_ROOT / "fixtures" / "engine" / "valid"
        for fixture in valid_directory.glob("*.json"):
            with self.subTest(fixture=fixture.name):
                value = json.loads(fixture.read_text(encoding="utf-8"))
                if "error" in fixture.name:
                    self.assertTrue(_is_envelope(value))
                    self.assertTrue(_is_engine_error_data(value["error"]["data"]))
                else:
                    self.assertTrue(_is_lifecycle_message(value))

        get_info_with_params = json.loads(
            (
                CONTRACT_ROOT
                / "fixtures"
                / "engine"
                / "invalid"
                / "engine-get-info-with-params.json"
            ).read_text(encoding="utf-8")
        )
        self.assertFalse(_is_lifecycle_message(get_info_with_params))

        unsafe_error_data = json.loads(
            (
                CONTRACT_ROOT
                / "fixtures"
                / "engine"
                / "invalid"
                / "unsafe-error-data.json"
            ).read_text(encoding="utf-8")
        )
        self.assertFalse(_is_engine_error_data(unsafe_error_data))

    def test_media_inspection_fixtures(self) -> None:
        for expected, directory in (
            (True, CONTRACT_ROOT / "fixtures" / "media" / "valid"),
            (False, CONTRACT_ROOT / "fixtures" / "media" / "invalid"),
        ):
            for fixture in directory.glob("*.json"):
                with self.subTest(fixture=fixture.name):
                    value = json.loads(fixture.read_text(encoding="utf-8"))
                    self.assertIs(_is_media_inspection_message(value), expected)
