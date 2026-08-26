"""Concrete EPUB execution behind the workload-agnostic job runner."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from threading import Lock, Thread

from mint_lingo_engine.epub.document import EpubPackageValidationError
from mint_lingo_engine.epub.export import (
    EpubPackageExporter,
    EpubPackageExportValidationError,
)
from mint_lingo_engine.epub.translation_checkpoint import EpubTranslationCheckpointStore
from mint_lingo_engine.epub.translation_workflow import EpubTranslationWorkflow
from mint_lingo_engine.processing.job import Job, JobId
from mint_lingo_engine.processing.progress import IndeterminateProgress, JobProgressNotification
from mint_lingo_engine.processing.runner import (
    JobCancellationAccepted,
    JobCancellationNotFound,
    JobCancelled,
    JobExecutionContext,
    JobRunner,
    JobStartConflict,
)
from mint_lingo_engine.providers.translation.base import LlmProvider
from mint_lingo_engine.providers.translation.ollama import (
    OllamaProvider,
    OllamaProviderError,
    OllamaProviderFailureCode,
)
from mint_lingo_engine.providers.translation.ollama_discovery import (
    OllamaDiscoveryError,
    OllamaModelDiscovery,
)
from mint_lingo_engine.translation.service import (
    TranslationService,
    TranslationServiceValidationError,
)

EPUB_TRANSLATION_WORKFLOW_ID = "document.epub.translate"


@dataclass(frozen=True)
class EpubJobFailureDiagnostic:
    """A safe, EPUB-owned explanation retained only for a failed EPUB job."""

    code: str
    message: str
    retryable: bool

    def __post_init__(self) -> None:
        for name in ("code", "message"):
            value = getattr(self, name)
            if not isinstance(value, str):
                raise TypeError(f"{name} must be a string")
            if not value or value.strip() != value:
                raise ValueError(f"{name} must not be blank or padded")
        if not isinstance(self.retryable, bool):
            raise TypeError("retryable must be a bool")


class _EpubJobDiagnosticError(RuntimeError):
    """Carry an already-sanitized EPUB failure across the runner boundary."""

    def __init__(self, diagnostic: EpubJobFailureDiagnostic) -> None:
        self.diagnostic = diagnostic
        super().__init__(diagnostic.code)


@dataclass(frozen=True)
class EpubJobInvocation:
    source_path: Path
    source_language: str
    target_language: str
    destination_path: Path
    artifact_root: Path
    checkpoint_namespace: str
    provider_id: str
    model_id: str

    @classmethod
    def from_payload(cls, payload: object) -> "EpubJobInvocation":
        if not isinstance(payload, dict) or set(payload) != {
            "sourcePath", "sourceLanguage", "targetLanguage", "destinationPath",
            "artifactRoot", "checkpointNamespace", "provider",
        }:
            raise ValueError("EPUB workflow payload is invalid")
        provider = payload["provider"]
        if not isinstance(provider, dict) or set(provider) != {"providerId", "modelId"}:
            raise ValueError("EPUB provider configuration is invalid")
        values = {
            name: payload[key]
            for name, key in (
                ("source_path", "sourcePath"), ("source_language", "sourceLanguage"),
                ("target_language", "targetLanguage"), ("destination_path", "destinationPath"),
                ("artifact_root", "artifactRoot"), ("checkpoint_namespace", "checkpointNamespace"),
                ("provider_id", "providerId"), ("model_id", "modelId"),
            )
            if key not in {"providerId", "modelId"}
        }
        values["provider_id"] = provider["providerId"]
        values["model_id"] = provider["modelId"]
        if any(not isinstance(value, str) or not value or value.strip() != value for value in values.values()):
            raise ValueError("EPUB workflow payload is invalid")
        if values["provider_id"] != "ollama":
            raise ValueError("EPUB provider is unsupported")
        return cls(
            source_path=Path(values["source_path"]), source_language=values["source_language"],
            target_language=values["target_language"], destination_path=Path(values["destination_path"]),
            artifact_root=Path(values["artifact_root"]), checkpoint_namespace=values["checkpoint_namespace"],
            provider_id=values["provider_id"], model_id=values["model_id"],
        )


class EpubJobExecutor:
    """Run one parsed EPUB invocation and retain only its exported reference."""

    def __init__(self, *, provider_factory: Callable[[EpubJobInvocation], LlmProvider] | None = None) -> None:
        self._provider_factory = provider_factory or _ollama_provider_for
        self._exports: dict[str, Path] = {}

    def invoke(
        self, invocation: EpubJobInvocation, context: JobExecutionContext,
        report_progress: Callable[[JobProgressNotification], None],
    ) -> None:
        report_progress(JobProgressNotification(context.job_id, "translating_epub", IndeterminateProgress()))
        workflow = EpubTranslationWorkflow(
            TranslationService(
                self._provider_factory(invocation),
                max_units_per_window=1,
            ),
            EpubTranslationCheckpointStore(invocation.artifact_root, checkpoint_namespace=invocation.checkpoint_namespace),
        )
        result = workflow.translate(
            {"sourcePath": str(invocation.source_path)}, source_language=invocation.source_language,
            target_language=invocation.target_language, cancellation=context.cancellation,
        )
        if isinstance(result, EpubPackageValidationError):
            raise _EpubJobDiagnosticError(
                EpubJobFailureDiagnostic(
                    code=result.code.value,
                    message=result.message,
                    retryable=result.retryable,
                )
            )
        report_progress(JobProgressNotification(context.job_id, "exporting_epub", IndeterminateProgress()))
        exported = EpubPackageExporter().export(result.rebuilt_package, invocation.destination_path, cancellation=context.cancellation)
        self._exports[context.job_id.value] = exported

    def exported_artifact_reference(self, job_id: str) -> str | None:
        path = self._exports.get(job_id)
        return None if path is None else str(path)


def _ollama_provider_for(invocation: EpubJobInvocation) -> LlmProvider:
    return OllamaProvider(OllamaModelDiscovery().discover(), invocation.model_id)


class EpubJobDispatcher:
    """Adapt one EPUB invocation to the shared runner without workflow discovery."""

    def __init__(
        self,
        runner: JobRunner,
        *,
        executor: EpubJobExecutor | None = None,
        on_progress: Callable[[JobProgressNotification], None] | None = None,
        on_terminal: Callable[[Job], None] | None = None,
    ) -> None:
        if not isinstance(runner, JobRunner):
            raise TypeError("runner must be a JobRunner")
        self._runner = runner
        self._executor = executor or EpubJobExecutor()
        self._on_progress = on_progress or (lambda _: None)
        self._on_terminal = on_terminal or (lambda _: None)
        self._failure_diagnostics: dict[str, EpubJobFailureDiagnostic] = {}
        self._failure_lock = Lock()

    def start(self, payload: object) -> Job | JobStartConflict:
        invocation = EpubJobInvocation.from_payload(payload)
        started = self._runner.start(
            lambda context: self._invoke(invocation, context)
        )
        if isinstance(started, Job):
            Thread(target=self._notify_terminal, args=(started.id,), daemon=True).start()
        return started

    def cancel(self, job_id: str) -> JobCancellationAccepted | JobCancellationNotFound:
        return self._runner.cancel(JobId(job_id))

    def get(self, job_id: str) -> Job | None:
        return self._runner.get_job(JobId(job_id))

    def exported_artifact_reference(self, job_id: str) -> str | None:
        return self._executor.exported_artifact_reference(job_id)

    def failure_diagnostic(self, job_id: str) -> EpubJobFailureDiagnostic | None:
        """Return the retained safe failure result without exposing cause details."""

        with self._failure_lock:
            return self._failure_diagnostics.get(job_id)

    def close(self) -> None:
        self._runner.close()

    def _notify_terminal(self, job_id: JobId) -> None:
        self._on_terminal(self._runner.wait_for_completion(job_id))

    def _invoke(
        self,
        invocation: EpubJobInvocation,
        context: JobExecutionContext,
    ) -> None:
        try:
            self._executor.invoke(invocation, context, self._on_progress)
        except JobCancelled:
            raise
        except Exception as error:
            with self._failure_lock:
                self._failure_diagnostics[context.job_id.value] = _sanitize_failure(error)
            raise


def _sanitize_failure(error: Exception) -> EpubJobFailureDiagnostic:
    """Map known failures to fixed user-safe EPUB diagnostics only."""

    if isinstance(error, _EpubJobDiagnosticError):
        return error.diagnostic
    if isinstance(error, OllamaDiscoveryError):
        return EpubJobFailureDiagnostic(
            code="epub.provider_unavailable",
            message=(
                "Ollama is unavailable. Start Ollama, confirm the selected model "
                "is installed, then try again."
            ),
            retryable=True,
        )
    if isinstance(error, OllamaProviderError):
        return _ollama_provider_diagnostic(error.code)
    if isinstance(error, TranslationServiceValidationError):
        return EpubJobFailureDiagnostic(
            code="epub.translation_response_invalid",
            message=(
                "Ollama returned a translation that could not be used. Try again, "
                "or choose a different model."
            ),
            retryable=True,
        )
    if isinstance(error, (EpubPackageExportValidationError, OSError)):
        return EpubJobFailureDiagnostic(
            code="epub.export_failed",
            message=(
                "The translated EPUB could not be saved. Check the destination "
                "and try again."
            ),
            retryable=True,
        )
    return EpubJobFailureDiagnostic(
        code="epub.processing_failed",
        message=(
            "The EPUB could not be processed. Try again, or choose a different "
            "EPUB or model."
        ),
        retryable=True,
    )


def _ollama_provider_diagnostic(
    code: OllamaProviderFailureCode,
) -> EpubJobFailureDiagnostic:
    """Map fixed provider failures into the EPUB-owned diagnostic boundary."""

    diagnostics = {
        OllamaProviderFailureCode.SERVICE_UNAVAILABLE: (
            "epub.provider_unavailable",
            "Ollama is unavailable. Start Ollama, confirm the selected model "
            "is installed, then try again.",
        ),
        OllamaProviderFailureCode.TIMEOUT: (
            "epub.provider_timeout",
            "Ollama took too long to respond. Try again, or choose a smaller model.",
        ),
        OllamaProviderFailureCode.REQUEST_REJECTED: (
            "epub.provider_request_rejected",
            "Ollama rejected the translation request. Confirm the selected model "
            "is available, then try again.",
        ),
        OllamaProviderFailureCode.MALFORMED_RESPONSE: (
            "epub.provider_response_malformed",
            "Ollama returned an unreadable response. Try again, or choose a "
            "different model.",
        ),
    }
    diagnostic_code, message = diagnostics[code]
    return EpubJobFailureDiagnostic(
        code=diagnostic_code,
        message=message,
        retryable=True,
    )
