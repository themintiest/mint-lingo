import json
from io import StringIO
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Event
import unittest

from mint_lingo_engine.epub.job_execution import (
    EpubJobDispatcher,
    EpubJobExecutor,
    EpubJobInvocation,
)
from mint_lingo_engine.epub.translation_batching import EpubTranslationBatchingPolicy
from mint_lingo_engine.epub.translation_recovery import (
    EpubRecoveryIndex,
    EpubRecoveryRecordStore,
)
from mint_lingo_engine.providers.translation.base import (
    LlmProvider,
    LlmProviderCapabilities,
    LlmProviderFailure,
    LlmProviderFailureCategory,
    LlmProviderFailureError,
    LlmProviderFailureRetryScope,
    LlmProviderResponseError,
    LlmProviderResponseFailureCode,
)
from mint_lingo_engine.providers.translation.ollama import OllamaProvider
from mint_lingo_engine.providers.translation.ollama_discovery import (
    OllamaDiscoveryError,
    OllamaModelCapabilities,
    OllamaModelInventory,
)
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
from mint_lingo_engine.api.ipc.worker import _job_state_changed_notification
from mint_lingo_engine.worker import handle_message, write_message


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

    def test_exposes_only_installed_completion_models_for_epub_selection(self) -> None:
        inventory = OllamaModelInventory(
            models=(
                OllamaModelCapabilities(
                    model_id="embed-only",
                    capabilities=("embedding",),
                    context_window_tokens=8_192,
                ),
                OllamaModelCapabilities(
                    model_id="translate-small",
                    capabilities=("completion",),
                    context_window_tokens=8_192,
                ),
                OllamaModelCapabilities(
                    model_id="translate-large",
                    capabilities=("completion",),
                    context_window_tokens=32_768,
                ),
            )
        )
        dispatcher = EpubJobDispatcher(
            JobRunner(self.root / "temporary-model-inventory"),
            model_inventory_loader=lambda: inventory,
        )
        self.addCleanup(dispatcher.close)

        response, should_shutdown = handle_message(
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "epub-model-inventory",
                "method": "epub.getModels",
            },
            epub_dispatcher=dispatcher,
        )

        self.assertFalse(should_shutdown)
        self.assertEqual(
            response,
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "epub-model-inventory",
                "result": {"modelIds": ["translate-small", "translate-large"]},
            },
        )

    def test_selected_inventory_model_keeps_capability_based_batching_in_python(self) -> None:
        inventory = OllamaModelInventory(
            models=(
                OllamaModelCapabilities(
                    model_id="translate-small",
                    capabilities=("completion",),
                    context_window_tokens=8_192,
                ),
                OllamaModelCapabilities(
                    model_id="translate-large",
                    capabilities=("completion",),
                    context_window_tokens=32_768,
                ),
            )
        )

        small_policy = EpubTranslationBatchingPolicy.from_capabilities(
            OllamaProvider(inventory, "translate-small").capabilities
        )
        large_policy = EpubTranslationBatchingPolicy.from_capabilities(
            OllamaProvider(inventory, "translate-large").capabilities
        )

        self.assertEqual(small_policy.max_units_per_window, 2)
        self.assertEqual(small_policy.overlap_units, 1)
        self.assertEqual(large_policy.max_units_per_window, 4)
        self.assertEqual(large_policy.overlap_units, 1)

    def test_reports_an_actionable_safe_error_when_model_inventory_is_unavailable(self) -> None:
        raw_detail = "Authorization: secret C:\\private\\models response"

        def unavailable_inventory() -> OllamaModelInventory:
            raise OllamaDiscoveryError(raw_detail)

        dispatcher = EpubJobDispatcher(
            JobRunner(self.root / "temporary-model-inventory-failure"),
            model_inventory_loader=unavailable_inventory,
        )
        self.addCleanup(dispatcher.close)

        response, should_shutdown = handle_message(
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "epub-model-inventory-failure",
                "method": "epub.getModels",
            },
            epub_dispatcher=dispatcher,
        )

        self.assertFalse(should_shutdown)
        assert response is not None
        self.assertEqual(response["error"]["code"], -32022)
        self.assertEqual(
            response["error"]["data"],
            {
                "providerCode": "ollama.inventory_unavailable",
                "retryable": True,
            },
        )
        self.assertNotIn(raw_detail, json.dumps(response))

    def test_retains_only_sanitized_failure_through_the_epub_boundary(self) -> None:
        terminal = Event()
        raw_detail = (
            r"C:\private\source.epub contains secret EPUB text and prompt; "
            "raw provider response; api_key=private; Traceback"
        )
        dispatcher = EpubJobDispatcher(
            JobRunner(self.root / "temporary"),
            executor=_FailingExecutor(  # type: ignore[arg-type]
                _user_directed_provider_failure(LlmProviderFailureCategory.SERVICE_UNAVAILABLE),
                raw_detail,
            ),
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
                            "Ollama is unavailable. Start Ollama, confirm the selected model "
                            "is installed, then try again."
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
            "headers",
        ):
            self.assertNotIn(sensitive_detail, serialized)

    def test_exposes_each_fixed_provider_failure_category_through_epub_get_failure(self) -> None:
        cases = (
            (
                LlmProviderFailureCategory.SERVICE_UNAVAILABLE,
                "epub.provider_unavailable",
                "Ollama is unavailable. Start Ollama, confirm the selected model "
                "is installed, then try again.",
            ),
            (
                LlmProviderFailureCategory.TIMEOUT,
                "epub.provider_timeout",
                "Ollama took too long to respond. Try again, or choose a smaller model.",
            ),
            (
                LlmProviderFailureCategory.REQUEST_REJECTED,
                "epub.provider_request_rejected",
                "Ollama rejected the translation request. Confirm the selected model "
                "is available, then try again.",
            ),
        )
        for failure_code, expected_code, expected_message in cases:
            with self.subTest(failure_code=failure_code):
                terminal = Event()
                dispatcher = EpubJobDispatcher(
                    JobRunner(self.root / f"temporary-{failure_code.value}"),
                    executor=_FailingExecutor(_user_directed_provider_failure(failure_code)),  # type: ignore[arg-type]
                    on_terminal=lambda _: terminal.set(),
                )
                self.addCleanup(dispatcher.close)

                started = dispatcher.start(_payload(self.root))

                self.assertTrue(terminal.wait(timeout=2))
                response, _ = handle_message(
                    {
                        "jsonrpc": "2.0",
                        "protocolVersion": "1.0",
                        "id": "failure-category",
                        "method": "epub.getFailure",
                        "params": {"jobId": started.id.value},
                    },
                    epub_dispatcher=dispatcher,
                )
                self.assertEqual(
                    response,
                    {
                        "jsonrpc": "2.0",
                        "protocolVersion": "1.0",
                        "id": "failure-category",
                        "result": {
                            "failure": {
                                "code": expected_code,
                                "message": expected_message,
                                "retryable": True,
                            }
                        },
                    },
                )

    def test_exposes_only_safe_epub_recovery_discovery_metadata(self) -> None:
        source = self.root / "book.epub"
        source.write_bytes(b"private source EPUB text")
        store = EpubRecoveryRecordStore(
            self.root / "artifacts",
            "f777042d-b756-4c9d-a47d-b6a6ea484288",
        )
        store.create(
            source_path=source,
            source_language="en",
            target_language="vi",
            provider_id="ollama",
            model_id="offline-model",
            checkpoint_namespace="book-translation",
        )
        recovery_index = EpubRecoveryIndex(self.root / "application-data")
        recovery_index.sync(
            store.path,
            store.mark_failed(
                _user_directed_provider_failure(
                    LlmProviderFailureCategory.TIMEOUT
                ).failure
            ),
        )
        dispatcher = EpubJobDispatcher(
            JobRunner(self.root / "temporary-recovery-discovery"),
            recovery_index=recovery_index,
        )
        self.addCleanup(dispatcher.close)

        listed, _ = handle_message(
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "recovery-list",
                "method": "epub.listRecoveries",
            },
            epub_dispatcher=dispatcher,
        )
        matched, _ = handle_message(
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "recovery-match",
                "method": "epub.findRecoveries",
                "params": {"sourcePath": str(source)},
            },
            epub_dispatcher=dispatcher,
        )

        expected_recovery = {
            "recoveryId": "f777042d-b756-4c9d-a47d-b6a6ea484288",
            "sourceLanguage": "en",
            "targetLanguage": "vi",
            "providerId": "ollama",
            "modelId": "offline-model",
            "failureCategory": "timeout",
        }
        self.assertEqual(
            listed,
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "recovery-list",
                "result": {"recoveries": [expected_recovery]},
            },
        )
        self.assertEqual(
            matched,
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "recovery-match",
                "result": {"recoveries": [expected_recovery]},
            },
        )
        serialized = json.dumps((listed, matched))
        self.assertNotIn(str(source), serialized)
        self.assertNotIn(str(store.path), serialized)
        self.assertNotIn("private source EPUB text", serialized)

    def test_resume_reconstructs_a_verified_invocation_without_client_artifact_paths(self) -> None:
        source = self.root / "book.epub"
        source.write_bytes(b"same selected EPUB")
        artifact_root = self.root / "private-artifacts"
        store = EpubRecoveryRecordStore(
            artifact_root,
            "f777042d-b756-4c9d-a47d-b6a6ea484288",
        )
        record = store.create(
            source_path=source,
            source_language="en",
            target_language="vi",
            provider_id="ollama",
            model_id="offline-model",
            checkpoint_namespace="existing-checkpoints",
        )
        record = store.mark_failed(
            _user_directed_provider_failure(
                LlmProviderFailureCategory.SERVICE_UNAVAILABLE
            ).failure
        )
        index = EpubRecoveryIndex(self.root / "application-data")
        index.sync(store.path, record)
        terminal = Event()
        executor = _CapturingExecutor()
        dispatcher = EpubJobDispatcher(
            JobRunner(self.root / "temporary-resume"),
            executor=executor,  # type: ignore[arg-type]
            recovery_index=index,
            on_terminal=lambda _: terminal.set(),
        )
        self.addCleanup(dispatcher.close)

        started = dispatcher.resume(
            {
                "recoveryId": record.recovery_id,
                "sourcePath": str(source),
                "destinationPath": str(self.root / "continued.epub"),
            }
        )

        self.assertTrue(terminal.wait(timeout=2))
        invocation = executor.invocations[0]
        self.assertEqual(invocation.source_path, source)
        self.assertEqual(invocation.destination_path, self.root / "continued.epub")
        self.assertEqual(invocation.artifact_root, artifact_root)
        self.assertEqual(invocation.checkpoint_namespace, "existing-checkpoints")
        self.assertEqual(invocation.source_language, "en")
        self.assertEqual(invocation.target_language, "vi")
        self.assertEqual(invocation.provider_id, "ollama")
        self.assertEqual(invocation.model_id, "offline-model")
        self.assertEqual(invocation.recovery_id, record.recovery_id)
        self.assertIsNotNone(dispatcher.get(started.id.value))

        with self.assertRaises(ValueError):
            dispatcher.resume(
                {
                    "recoveryId": record.recovery_id,
                    "sourcePath": str(self.root / "other.epub"),
                    "destinationPath": str(self.root / "continued.epub"),
                }
            )

    def test_generic_terminal_notification_is_byte_stable_and_has_no_failure_details(self) -> None:
        terminal = Event()
        raw_detail = "C:\\private\\book.epub prompt secret response Authorization: token"
        dispatcher = EpubJobDispatcher(
            JobRunner(self.root / "temporary-terminal-notification"),
            executor=_FailingExecutor(  # type: ignore[arg-type]
                _retryable_malformed_response(),
                raw_detail,
            ),
            on_terminal=lambda _: terminal.set(),
        )
        self.addCleanup(dispatcher.close)

        started = dispatcher.start(_payload(self.root))
        self.assertTrue(terminal.wait(timeout=2))
        job = dispatcher.get(started.id.value)
        assert job is not None

        output = StringIO()
        write_message(output, _job_state_changed_notification(job))
        self.assertEqual(
            output.getvalue(),
            (
                '{"jsonrpc":"2.0","protocolVersion":"1.0",'
                '"method":"job.stateChanged","params":{"jobId":"'
                f'{started.id.value}","lifecycle":"failed"}}}}\n'
            ),
        )
        self.assertNotIn(raw_detail, output.getvalue())

    def test_retains_only_the_safe_provider_neutral_malformed_response_diagnostic(self) -> None:
        terminal = Event()
        raw_detail = (
            r"C:\private\source.epub prompt secret source text; raw provider response; "
            "Authorization: private"
        )
        dispatcher = EpubJobDispatcher(
            JobRunner(self.root / "temporary-provider-response"),
            executor=_FailingExecutor(  # type: ignore[arg-type]
                _retryable_malformed_response(),
                raw_detail,
            ),
            on_terminal=lambda _: terminal.set(),
        )
        self.addCleanup(dispatcher.close)

        started = dispatcher.start(_payload(self.root))

        self.assertTrue(terminal.wait(timeout=2))
        diagnostic = dispatcher.failure_diagnostic(started.id.value)
        assert diagnostic is not None
        self.assertEqual(diagnostic.code, "epub.provider_response_malformed")
        self.assertEqual(
            diagnostic.message,
            "The translation provider returned an unreadable response. Try again, "
            "or choose a different model.",
        )
        self.assertTrue(diagnostic.retryable)
        self.assertNotIn(raw_detail, diagnostic.message)

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
        self.assertEqual(diagnostic.code, "epub.translation_response_invalid")
        self.assertEqual(
            diagnostic.message,
            "Ollama returned a translation that could not be used. Try again, "
            "or choose a different model.",
        )
        self.assertNotIn(raw_unit_id, diagnostic.message)
        response, _ = handle_message(
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "invalid-translation",
                "method": "epub.getFailure",
                "params": {"jobId": started.id.value},
            },
            epub_dispatcher=dispatcher,
        )
        self.assertEqual(
            response,
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "invalid-translation",
                "result": {
                    "failure": {
                        "code": "epub.translation_response_invalid",
                        "message": (
                            "Ollama returned a translation that could not be used. Try again, "
                            "or choose a different model."
                        ),
                        "retryable": True,
                    }
                },
            },
        )


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


class _CapturingExecutor:
    def __init__(self) -> None:
        self.invocations: list[EpubJobInvocation] = []

    def invoke(self, invocation, _context, _report_progress) -> None:
        self.invocations.append(invocation)

    def exported_artifact_reference(self, _job_id: str) -> str | None:
        return None


class _FailingExecutor:
    def __init__(self, error: Exception, raw_detail: str | None = None) -> None:
        self._error = error
        self._raw_detail = raw_detail

    def invoke(self, _invocation, _context, _report_progress) -> None:
        if self._raw_detail is not None:
            raise self._error from RuntimeError(self._raw_detail)
        raise self._error

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


def _retryable_malformed_response() -> LlmProviderResponseError:
    return LlmProviderResponseError(
        LlmProviderResponseFailureCode.MALFORMED_RESPONSE,
        retryable=True,
    )


def _user_directed_provider_failure(
    category: LlmProviderFailureCategory,
) -> LlmProviderFailureError:
    return LlmProviderFailureError(
        LlmProviderFailure(
            category=category,
            retryable=True,
            retry_scope=LlmProviderFailureRetryScope.USER_DIRECTED_RESUME,
        )
    )


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
