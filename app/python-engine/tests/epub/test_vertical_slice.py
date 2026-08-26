from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Event
import unittest
import xml.etree.ElementTree as ElementTree
import zipfile

from mint_lingo_engine.api.ipc.worker import handle_message
from mint_lingo_engine.epub.document import EpubDocumentArtifact
from mint_lingo_engine.epub.inspection import EpubPackageInspector
from mint_lingo_engine.epub.job_execution import EpubJobDispatcher, EpubJobExecutor
from mint_lingo_engine.epub.source import EpubSourceReference
from mint_lingo_engine.processing.progress import (
    DeterminateProgress,
    IndeterminateProgress,
    JobProgressNotification,
)
from mint_lingo_engine.processing.runner import JobRunner
from mint_lingo_engine.providers.translation.base import (
    LlmProvider,
    LlmProviderCapabilities,
)
from mint_lingo_engine.translation.models import (
    TranslatedTextUnit,
    TranslationArtifact,
    TranslationRequest,
)


class EpubVerticalSliceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(self.enterContext(TemporaryDirectory()))

    def test_translates_exports_and_reopens_an_epub_with_preserved_resources(self) -> None:
        source = self.root / "source.epub"
        destination = self.root / "translated.epub"
        _write_epub_fixture(source)
        source_bytes = source.read_bytes()

        original = EpubPackageInspector().inspect(EpubSourceReference(source))
        self.assertIsInstance(original, EpubDocumentArtifact)
        assert isinstance(original, EpubDocumentArtifact)
        self.assertEqual(original.package_metadata.language, "en")
        self.assertEqual(original.navigation.href, "OEBPS/nav.xhtml")

        terminal = Event()
        provider = _FakeLlmProvider(context_window_tokens=8_192)
        progress: list[JobProgressNotification] = []
        dispatcher = EpubJobDispatcher(
            JobRunner(self.root / "temporary"),
            executor=EpubJobExecutor(provider_factory=lambda _: provider),
            on_progress=progress.append,
            on_terminal=lambda _: terminal.set(),
        )
        self.addCleanup(dispatcher.close)

        started, _ = handle_message(
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "start-epub-translation",
                "method": "job.start",
                "params": {
                    "workflowId": "document.epub.translate",
                    "workflowPayload": {
                        "sourcePath": str(source),
                        "sourceLanguage": "en",
                        "targetLanguage": "vi",
                        "destinationPath": str(destination),
                        "artifactRoot": str(self.root / "artifacts"),
                        "checkpointNamespace": "fixture-translation",
                        "provider": {
                            "providerId": "ollama",
                            "modelId": "offline-test-model",
                        },
                    },
                },
            },
            epub_dispatcher=dispatcher,
        )
        assert started is not None
        job_id = started["result"]["job"]["jobId"]
        self.assertTrue(terminal.wait(timeout=2))

        job, _ = handle_message(
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "read-completed-job",
                "method": "job.get",
                "params": {"jobId": job_id},
            },
            epub_dispatcher=dispatcher,
        )
        self.assertEqual(job, {
            "jsonrpc": "2.0",
            "protocolVersion": "1.0",
            "id": "read-completed-job",
            "result": {"job": {"jobId": job_id, "lifecycle": "completed"}},
        })

        exported, _ = handle_message(
            {
                "jsonrpc": "2.0",
                "protocolVersion": "1.0",
                "id": "read-export",
                "method": "epub.getExport",
                "params": {"jobId": job_id},
            },
            epub_dispatcher=dispatcher,
        )
        self.assertEqual(exported, {
            "jsonrpc": "2.0",
            "protocolVersion": "1.0",
            "id": "read-export",
            "result": {"exportedArtifactReference": str(destination)},
        })
        self.assertEqual(source.read_bytes(), source_bytes)
        self.assertEqual(progress[0].stage_id, "translating_epub")
        self.assertIsInstance(progress[0].progress, IndeterminateProgress)
        determinate_translation = [
            notification.progress
            for notification in progress
            if notification.stage_id == "translating_epub"
            and isinstance(notification.progress, DeterminateProgress)
        ]
        self.assertEqual(
            [
                (notification.completed_units, notification.total_units)
                for notification in determinate_translation
            ],
            [(0, 2), (2, 2)],
        )
        self.assertEqual(progress[-1].stage_id, "exporting_epub")
        self.assertIsInstance(progress[-1].progress, IndeterminateProgress)

        translated = EpubPackageInspector().inspect(EpubSourceReference(destination))
        self.assertIsInstance(translated, EpubDocumentArtifact)
        assert isinstance(translated, EpubDocumentArtifact)
        self.assertEqual(translated.package_metadata.language, "vi")
        with zipfile.ZipFile(destination) as archive:
            chapter = ElementTree.fromstring(archive.read("OEBPS/chapter.xhtml"))
            self.assertEqual(chapter.attrib["lang"], "vi")
            self.assertEqual(
                [node.text for node in chapter.iter() if node.tag.endswith("p")],
                ["Đoạn đầu", "Đoạn hai"],
            )
            navigation = ElementTree.fromstring(archive.read("OEBPS/nav.xhtml"))
            link = next(node for node in navigation.iter() if node.tag.endswith("a"))
            self.assertEqual(link.attrib["href"], "chapter.xhtml#start")
            self.assertEqual(archive.read("OEBPS/book.css"), b"p { color: #123456; }")
            self.assertEqual(archive.read("OEBPS/images/cover.jpg"), b"image-bytes")
            self.assertEqual(archive.read("OEBPS/fonts/book.otf"), b"font-bytes")

        self.assertEqual(
            provider.request_unit_ids,
            [("chapter.text.1", "chapter.text.2")],
        )
        checkpoint_directory = (
            self.root / "artifacts" / "epub-translation" / "fixture-translation"
        )
        self.assertEqual(len(list(checkpoint_directory.glob("*.json"))), 2)
        self.assertTrue(all("Vietnamese" in instruction for instruction in provider.instructions))

    def test_rejects_an_oversized_unit_without_provider_input_or_source_details(self) -> None:
        source = self.root / "source.epub"
        destination = self.root / "translated.epub"
        secret_source_text = "confidential EPUB source text " * 400
        _write_epub_fixture(source, chapter_texts=(secret_source_text, "Second"))
        terminal = Event()
        provider = _FakeLlmProvider(context_window_tokens=32_768)
        dispatcher = EpubJobDispatcher(
            JobRunner(self.root / "temporary"),
            executor=EpubJobExecutor(provider_factory=lambda _: provider),
            on_terminal=lambda _: terminal.set(),
        )
        self.addCleanup(dispatcher.close)

        started = dispatcher.start(
            _workflow_payload(
                source=source,
                destination=destination,
                artifact_root=self.root / "artifacts",
                checkpoint_namespace="oversized-fixture",
            )
        )

        self.assertTrue(terminal.wait(timeout=2))
        job = dispatcher.get(started.id.value)
        assert job is not None
        self.assertEqual(job.lifecycle.value, "failed")
        self.assertEqual(provider.request_unit_ids, [])
        self.assertFalse(destination.exists())
        self.assertFalse((self.root / "artifacts").exists())
        diagnostic = dispatcher.failure_diagnostic(started.id.value)
        assert diagnostic is not None
        self.assertEqual(diagnostic.code, "epub.translation_unit_too_large")
        self.assertEqual(
            diagnostic.message,
            "This EPUB contains text that is too large to translate safely. "
            "Split the source content and try again.",
        )
        self.assertFalse(diagnostic.retryable)
        self.assertNotIn(secret_source_text, diagnostic.message)


class _FakeLlmProvider(LlmProvider):
    def __init__(self, *, context_window_tokens: int | None = None) -> None:
        self._capabilities = LlmProviderCapabilities(
            model_ids=("offline-test-model",),
            context_window_tokens=context_window_tokens,
            supports_structured_output=True,
            supports_streaming=False,
        )
        self.request_unit_ids: list[tuple[str, ...]] = []
        self.instructions: list[str] = []

    @property
    def capabilities(self) -> LlmProviderCapabilities:
        return self._capabilities

    def translate(
        self,
        request: TranslationRequest,
        instructions: str,
    ) -> TranslationArtifact:
        translations = {
            "chapter.text.1": "Đoạn đầu",
            "chapter.text.2": "Đoạn hai",
        }
        self.instructions.append(instructions)
        self.request_unit_ids.append(
            tuple(unit.unit_id for unit in request.artifact.units)
        )
        return TranslationArtifact(
            target_language=request.target_language,
            units=tuple(
                TranslatedTextUnit(unit.unit_id, translations[unit.unit_id])
                for unit in request.artifact.units
            ),
        )


def _workflow_payload(
    *,
    source: Path,
    destination: Path,
    artifact_root: Path,
    checkpoint_namespace: str,
) -> dict[str, object]:
    return {
        "sourcePath": str(source),
        "sourceLanguage": "en",
        "targetLanguage": "vi",
        "destinationPath": str(destination),
        "artifactRoot": str(artifact_root),
        "checkpointNamespace": checkpoint_namespace,
        "provider": {"providerId": "ollama", "modelId": "offline-test-model"},
    }


def _write_epub_fixture(
    path: Path,
    *,
    chapter_texts: tuple[str, str] = ("First", "Second"),
) -> None:
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr(
            "mimetype",
            "application/epub+zip",
            compress_type=zipfile.ZIP_STORED,
        )
        archive.writestr(
            "META-INF/container.xml",
            '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
        )
        archive.writestr(
            "OEBPS/content.opf",
            '<package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata><dc:title>Fixture book</dc:title><dc:language>en</dc:language></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/><item id="css" href="book.css" media-type="text/css"/><item id="cover" href="images/cover.jpg" media-type="image/jpeg"/><item id="font" href="fonts/book.otf" media-type="application/vnd.ms-opentype"/></manifest><spine><itemref idref="chapter"/></spine></package>',
        )
        archive.writestr(
            "OEBPS/nav.xhtml",
            '<html xmlns="http://www.w3.org/1999/xhtml" lang="en"><body><nav><ol><li><a href="chapter.xhtml#start">Chapter</a></li></ol></nav></body></html>',
        )
        archive.writestr(
            "OEBPS/chapter.xhtml",
            '<html xmlns="http://www.w3.org/1999/xhtml" lang="en"><body>'
            f'<p id="start">{chapter_texts[0]}</p><p>{chapter_texts[1]}</p>'
            "</body></html>",
        )
        archive.writestr("OEBPS/book.css", b"p { color: #123456; }")
        archive.writestr("OEBPS/images/cover.jpg", b"image-bytes")
        archive.writestr("OEBPS/fonts/book.otf", b"font-bytes")
