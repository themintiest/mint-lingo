import json
import subprocess
import sys
import unittest
from pathlib import Path


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
