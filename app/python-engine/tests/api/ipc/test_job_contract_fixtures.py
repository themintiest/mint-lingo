import json
import re
import unittest
from pathlib import Path
from typing import Any


CONTRACT_ROOT = Path(__file__).parents[5] / "shared" / "schemas" / "ipc" / "v1"
_JOB_ID_PATTERN = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
)
_LIFECYCLES = {"created", "running", "completed", "failed", "cancelled"}


def _is_job_id(value: Any) -> bool:
    return isinstance(value, str) and _JOB_ID_PATTERN.fullmatch(value) is not None


def _is_job_state(value: Any) -> bool:
    return (
        isinstance(value, dict)
        and set(value) == {"jobId", "lifecycle"}
        and _is_job_id(value["jobId"])
        and value["lifecycle"] in _LIFECYCLES
    )


def _is_job_management_message(value: Any) -> bool:
    if not isinstance(value, dict):
        return False
    if value.get("jsonrpc") != "2.0" or value.get("protocolVersion") != "1.0":
        return False

    method = value.get("method")
    params = value.get("params")
    if method == "job.start":
        return (
            set(value) == {"jsonrpc", "protocolVersion", "id", "method", "params"}
            and isinstance(value.get("id"), (str, int))
            and not isinstance(value.get("id"), bool)
            and isinstance(params, dict)
            and set(params) == {"workflowId", "workflowPayload"}
            and isinstance(params["workflowId"], str)
            and bool(params["workflowId"])
            and isinstance(params["workflowPayload"], dict)
        )
    if method in {"job.cancel", "job.get"}:
        return (
            set(value) == {"jsonrpc", "protocolVersion", "id", "method", "params"}
            and isinstance(value.get("id"), (str, int))
            and not isinstance(value.get("id"), bool)
            and isinstance(params, dict)
            and set(params) == {"jobId"}
            and _is_job_id(params["jobId"])
        )
    if method == "job.stateChanged":
        return set(value) == {"jsonrpc", "protocolVersion", "method", "params"} and _is_job_state(params)
    if method == "job.progress":
        if set(value) != {"jsonrpc", "protocolVersion", "method", "params"}:
            return False
        if not isinstance(params, dict) or set(params) != {"jobId", "stageId", "progress"}:
            return False
        if not _is_job_id(params["jobId"]) or not isinstance(params["stageId"], str) or not params["stageId"]:
            return False
        progress = params["progress"]
        if not isinstance(progress, dict):
            return False
        if progress.get("kind") == "indeterminate":
            return set(progress) == {"kind"}
        return (
            set(progress) == {"kind", "completedUnits", "totalUnits"}
            and progress.get("kind") == "determinate"
            and isinstance(progress.get("completedUnits"), int)
            and not isinstance(progress.get("completedUnits"), bool)
            and isinstance(progress.get("totalUnits"), int)
            and not isinstance(progress.get("totalUnits"), bool)
            and 0 <= progress["completedUnits"] <= progress["totalUnits"]
            and progress["totalUnits"] > 0
        )

    result = value.get("result")
    if isinstance(result, dict) and set(value) == {"jsonrpc", "protocolVersion", "id", "result"}:
        if set(result) == {"job"}:
            return _is_job_state(result["job"])
        return (
            set(result) == {"jobId", "cancellationRequested"}
            and _is_job_id(result["jobId"])
            and result["cancellationRequested"] is True
        )

    error = value.get("error")
    if not isinstance(error, dict) or set(value) != {"jsonrpc", "protocolVersion", "id", "error"}:
        return False
    data = error.get("data")
    if not isinstance(data, dict):
        return False
    if error.get("code") == -32020:
        return (
            error.get("message") == "Another job is already active."
            and data
            == {
                "jobCode": "job.active_job_conflict",
                "retryable": False,
                "activeJobId": data.get("activeJobId"),
            }
            and _is_job_id(data["activeJobId"])
        )
    return (
        error.get("code") == -32021
        and error.get("message") == "Job not found."
        and data == {"jobCode": "job.not_found", "retryable": False}
    )


class JobIpcContractFixtureTest(unittest.TestCase):
    def test_job_management_fixtures(self) -> None:
        for expected, directory in (
            (True, CONTRACT_ROOT / "fixtures" / "jobs" / "valid"),
            (False, CONTRACT_ROOT / "fixtures" / "jobs" / "invalid"),
        ):
            for fixture in directory.glob("*.json"):
                with self.subTest(fixture=fixture.name):
                    value = json.loads(fixture.read_text(encoding="utf-8"))
                    self.assertIs(_is_job_management_message(value), expected)
