from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Event
import unittest

from mint_lingo_engine.epub.job_execution import (
    EpubJobDispatcher,
    EpubJobInvocation,
)
from mint_lingo_engine.processing.progress import (
    IndeterminateProgress,
    JobProgressNotification,
)
from mint_lingo_engine.processing.runner import JobRunner


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
