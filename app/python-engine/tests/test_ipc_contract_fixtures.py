import json
import unittest
from pathlib import Path
from typing import Any


CONTRACT_ROOT = Path(__file__).parents[3] / "shared" / "schemas" / "ipc" / "v1"


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
