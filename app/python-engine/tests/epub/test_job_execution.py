import json
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Event
import unittest

from mint_lingo_engine.epub.job_execution import (
    EpubJobDispatcher,
    EpubJobExecutor,
    EpubJobInvocation,
)
from mint_lingo_engine.providers.translation.base import (
    LlmProvider,
    LlmProviderCapabilities,
)
from mint_lingo_engine.providers.translation.ollama import OllamaProviderError
from mint_lingo_engine.processing.progress import (
    IndeterminateProgress,
    JobProgressNotification,
)
from mint_lingo_engine.processing.runner import JobRunner
from mint_lingo_engine.translation.models import TranslationArtifact, TranslationRequest
from mint_lingo_engine.translation.service import TranslationServiceValidationError
from mint_lingo_engine.translation.validation import (
    TranslationValidationError,
    TranslationValidationErrorCode,
)
from mint_lingo_engine.worker import handle_message


class EpubJobExecutionTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(self.enterContext(TemporaryDirectory()))

    def test_requires_a_concrete_provider_configured_epub_payload(self) -> None:
        with self.assertRaisesRegex(ValueError, "payload is invalid"):
            EpubJobInvocation.from_payload({"sourcePath": "book.epub"})

        with self.assertRaisesRegex(ValueError, "provider is unsupported"):
            EpubJobInvocation.from_payload({
                **_payload(self.root),
                "provider": {"providerId": "other", "modelId": "model"},
            })

    def test_runs_through_the_shared_runner_and_retains_only_export_reference(self) -> None:
        terminal = Event()
        progress: list[JobProgressNotification] = []
        executor = _FakeExecutor(self.root / "translated.epub")
        dispatcher = EpubJobDispatcher(
            JobRunner(self.root / "temporary"),
            executor=executor,  # type: ignore[arg-type]
            on_progress=progress.append,
            on_terminal=lambda _: terminal.set(),
        )
        self.addCleanup(dispatcher.close)

        started = dispatcher.start(_payload(self.root))

        self.assertTrue(terminal.wait(timeout=2))
        job = dispatcher.get(started.id.value)
        assert job is not None
        self.assertEqual(job.lifecycle.value, "completed")
        self.assertEqual(
            dispatcher.exported_artifact_reference(started.id.value),
            str(self.root / "translated.epub"),
        )
        self.assertEqual(progress[0].stage_id, "translating_epub")

    def test_production_executor_constructs_a_bounded_service_before_inspection(self) -> None:
        terminal = Event()
        dispatcher = EpubJobDispatcher(
            JobRunner(self.root / "temporary"),
            executor=EpubJobExecutor(provider_factory=lambda _: _UnusedProvider()),
            on_terminal=lambda _: terminal.set(),
        )
        self.addCleanup(dispatcher.close)

        started = dispatcher.start(_payload(self.root))

        self.assertTrue(terminal.wait(timeout=2))
        job = dispatcher.get(started.id.value)
        assert job is not None
        self.assertEqual(job.lifecycle.value, "failed")
        diagnostic = dispatcher.failure_diagnostic(started.id.value)
        assert diagnostic is not None
        self.assertEqual(diagnostic.code, "epub.source_not_found")

    def test_retains_only_sanitized_failure_through_the_epub_boundary(self) -> None:
        terminal = Event()
        raw_detail = (
            r"C:\private\source.epub contains secret EPUB text and prompt; "
            "raw provider response; api_key=private; Traceback"
        )
        dispatcher = EpubJobDispatcher(
            JobRunner(self.root / "temporary"),
            executor=_FailingExecutor(raw_detail),  # type: ignore[arg-type]
            on_terminal=lambda _: terminal.set(),
        )
        self.addCleanup(dispatcher.close)

        started = dispatcher.start(_payload(self.root))

        self.assertTrue(terminal.wait(timeout=2))
        job = dispatcher.get(started.id.value)
        assert job is not None
        self.assertEqual(job.lifecycle.value, "failed")
        self.assertEqual(
            handle_message(
                {
                    "jsonrpc": "2.0",
                    "protocolVersion": "1.0",
                    "id": "failure-001",
                    "method": "epub.getFailure",
                    "params": {"jobId": started.id.value},
                },
                epub_dispatcher=dispatcher,
            )[0],
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "failure-001",
                "result": {
                    "failure": {
                        "code": "epub.provider_unavailable",
                        "message": (
                            "Ollama could not translate this EPUB. Confirm it is running and "
                            "the selected model is installed, then try again."
                        ),
                        "retryable": True,
                    }
                },
            },
        )
        job_response, _ = handle_message(
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "job-001",
                "method": "job.get",
                "params": {"jobId": started.id.value},
            },
            epub_dispatcher=dispatcher,
        )
        self.assertEqual(
            job_response,
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "job-001",
                "result": {
                    "job": {"jobId": started.id.value, "lifecycle": "failed"}
                },
            },
        )
        serialized = json.dumps(handle_message(
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "failure-002",
                "method": "epub.getFailure",
                "params": {"jobId": started.id.value},
            },
            epub_dispatcher=dispatcher,
        )[0])
        for sensitive_detail in (
            r"C:\private\source.epub",
            "secret EPUB text",
            "prompt",
            "raw provider response",
            "api_key=private",
            "Traceback",
        ):
            self.assertNotIn(sensitive_detail, serialized)

    def test_retains_a_safe_validation_category_without_unit_details(self) -> None:
        raw_unit_id = "chapter.secret.unit"
        terminal = Event()
        dispatcher = EpubJobDispatcher(
            JobRunner(self.root / "temporary"),
            executor=_ValidationFailingExecutor(raw_unit_id),  # type: ignore[arg-type]
            on_terminal=lambda _: terminal.set(),
        )
        self.addCleanup(dispatcher.close)

        started = dispatcher.start(_payload(self.root))
        self.assertTrue(terminal.wait(timeout=2))
        job = dispatcher.get(started.id.value)
        assert job is not None

        self.assertEqual(job.lifecycle.value, "failed")
        diagnostic = dispatcher.failure_diagnostic(started.id.value)
        assert diagnostic is not None
        self.assertEqual(diagnostic.code, "epub.translation_empty_entries")
        self.assertEqual(
            diagnostic.message,
            "The selected model returned empty translation entries. Try again or "
            "choose a different model.",
        )
        self.assertNotIn(raw_unit_id, diagnostic.message)


class _FakeExecutor:
    def __init__(self, exported_path: Path) -> None:
        self._exported_path = exported_path
        self._exports: dict[str, Path] = {}

    def invoke(self, _invocation, context, report_progress) -> None:
        report_progress(
            JobProgressNotification(
                context.job_id,
                "translating_epub",
                IndeterminateProgress(),
            )
        )
        self._exports[context.job_id.value] = self._exported_path

    def exported_artifact_reference(self, job_id: str) -> str | None:
        path = self._exports.get(job_id)
        return None if path is None else str(path)


class _FailingExecutor:
    def __init__(self, raw_detail: str) -> None:
        self._raw_detail = raw_detail

    def invoke(self, _invocation, _context, _report_progress) -> None:
        raise OllamaProviderError(self._raw_detail)

    def exported_artifact_reference(self, _job_id: str) -> str | None:
        return None


class _UnusedProvider(LlmProvider):
    @property
    def capabilities(self) -> LlmProviderCapabilities:
        return LlmProviderCapabilities(
            model_ids=("offline-model",),
            context_window_tokens=None,
            supports_structured_output=True,
            supports_streaming=False,
        )

    def translate(
        self,
        _request: TranslationRequest,
        _instructions: str,
    ) -> TranslationArtifact:
        raise AssertionError("source validation must run before provider translation")


class _ValidationFailingExecutor:
    def __init__(self, raw_unit_id: str) -> None:
        self._raw_unit_id = raw_unit_id

    def invoke(self, _invocation, _context, _report_progress) -> None:
        raise TranslationServiceValidationError(
            TranslationValidationError(
                code=TranslationValidationErrorCode.EMPTY_TRANSLATED_TEXT,
                message=f"Translated result for unit ID {self._raw_unit_id!r} is empty.",
                unit_ids=(self._raw_unit_id,),
            )
        )

    def exported_artifact_reference(self, _job_id: str) -> str | None:
        return None


def _payload(root: Path) -> dict[str, object]:
    return {
        "sourcePath": str(root / "source.epub"),
        "sourceLanguage": "en",
        "targetLanguage": "vi",
        "destinationPath": str(root / "translated.epub"),
        "artifactRoot": str(root / "artifacts"),
        "checkpointNamespace": "book-translation",
        "provider": {"providerId": "ollama", "modelId": "offline-model"},
    }
