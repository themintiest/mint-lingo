from collections.abc import Callable
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Event
import unittest
import xml.etree.ElementTree as ElementTree
import zipfile

from mint_lingo_engine.epub.chapter_context import EpubChapterContextWindowBuilder
from mint_lingo_engine.epub.export import EpubPackageExporter
from mint_lingo_engine.epub.job_execution import EpubJobDispatcher, EpubJobExecutor
from mint_lingo_engine.epub.translation_batching import EpubTranslationBatchingPolicy
from mint_lingo_engine.epub.translation_checkpoint import EpubTranslationCheckpointStore
from mint_lingo_engine.epub.translation_workflow import EpubTranslationWorkflow
from mint_lingo_engine.processing.runner import CancellationToken, JobCancelled, JobRunner
from mint_lingo_engine.providers.translation.base import (
    LlmProvider,
    LlmProviderCapabilities,
)
from mint_lingo_engine.translation.models import (
    TranslatedTextUnit,
    TranslationArtifact,
    TranslationRequest,
)
from mint_lingo_engine.translation.service import TranslationService


_FRAGMENT_IDS = (
    "chapter.text.1.fragment.1",
    "chapter.text.1.fragment.2",
    "chapter.text.1.fragment.3",
)


class EpubTranslationQualityRegressionTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(self.enterContext(TemporaryDirectory()))

    def test_retries_copied_fragment_once_then_reconstructs_and_exports(self) -> None:
        source = self.root / "source.epub"
        destination = self.root / "translated.epub"
        _write_epub_fixture(source)
        source_bytes = source.read_bytes()
        copied_source = _fragment_source().split("  ", 1)[0]
        provider = _ScriptedProvider(
            responses=(
                {
                    _FRAGMENT_IDS[0]: "Ban dich mo dau. " + copied_source,
                    _FRAGMENT_IDS[1]: "Cau thu hai.",
                },
                {_FRAGMENT_IDS[0]: "Cau thu nhat."},
                {_FRAGMENT_IDS[2]: "Cau thu ba."},
            )
        )
        checkpoint_store = self._checkpoint_store("copied-source")

        result = self._workflow(provider, checkpoint_store).translate(
            {"sourcePath": str(source)},
            source_language="en",
            target_language="vi",
        )
        EpubPackageExporter().export(result.rebuilt_package, destination)

        self.assertEqual(
            _request_unit_ids(provider.calls),
            [
                _FRAGMENT_IDS[:2],
                _FRAGMENT_IDS[:1],
                _FRAGMENT_IDS[2:],
            ],
        )
        self.assertEqual(
            _context_unit_ids(provider.calls),
            [
                _FRAGMENT_IDS[2:],
                _FRAGMENT_IDS[2:],
                _FRAGMENT_IDS[1:2],
            ],
        )
        self.assertEqual(
            [unit.unit_id for unit in result.translation.units],
            list(_FRAGMENT_IDS),
        )
        self.assertEqual(
            [
                unit.translated_text
                for unit in result.translation.units
            ],
            ["Cau thu nhat.", "Cau thu hai.", "Cau thu ba."],
        )
        self.assertEqual(source.read_bytes(), source_bytes)
        self.assertTrue(destination.exists())
        self.assertEqual(
            len(list((self.root / "artifacts" / "epub-translation" / "copied-source").glob("*.json"))),
            3,
        )
        with zipfile.ZipFile(destination) as archive:
            chapter = ElementTree.fromstring(archive.read("OEBPS/chapter.xhtml"))
            paragraph = next(node for node in chapter.iter() if node.tag.endswith("p"))
            self.assertEqual(
                paragraph.text,
                "Cau thu nhat.  Cau thu hai.\nCau thu ba.",
            )
            navigation = ElementTree.fromstring(archive.read("OEBPS/nav.xhtml"))
            link = next(node for node in navigation.iter() if node.tag.endswith("a"))
            self.assertEqual(link.attrib["href"], "chapter.xhtml#start")
            self.assertEqual(archive.read("OEBPS/book.css"), b"p { color: #123456; }")
            self.assertEqual(archive.read("OEBPS/images/cover.jpg"), b"image-bytes")
            self.assertEqual(archive.read("OEBPS/fonts/book.otf"), b"font-bytes")

    def test_repeated_copied_fragment_fails_through_safe_diagnostic_without_export(self) -> None:
        source = self.root / "private-source.epub"
        destination = self.root / "translated.epub"
        _write_epub_fixture(source)
        copied_source = _fragment_source().split("  ", 1)[0]
        secret_prompt = "do not disclose this test prompt"
        provider = _ScriptedProvider(
            responses=(
                {
                    _FRAGMENT_IDS[0]: secret_prompt + ". " + copied_source,
                    _FRAGMENT_IDS[1]: "Cau thu hai.",
                },
                {_FRAGMENT_IDS[0]: secret_prompt + ". " + copied_source},
            )
        )
        terminal = Event()
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
                checkpoint_namespace="rejected-copy",
            )
        )

        self.assertTrue(terminal.wait(timeout=2))
        job = dispatcher.get(started.id.value)
        assert job is not None
        self.assertEqual(job.lifecycle.value, "failed")
        self.assertEqual(_request_unit_ids(provider.calls), [_FRAGMENT_IDS[:2], _FRAGMENT_IDS[:1]])
        diagnostic = dispatcher.failure_diagnostic(started.id.value)
        assert diagnostic is not None
        self.assertEqual(diagnostic.code, "epub.translation_response_invalid")
        self.assertTrue(diagnostic.retryable)
        self.assertNotIn(copied_source, diagnostic.message)
        self.assertNotIn(secret_prompt, diagnostic.message)
        self.assertNotIn(str(source), diagnostic.message)
        self.assertFalse(destination.exists())
        self.assertFalse((self.root / "artifacts" / "epub-translation" / "rejected-copy").exists())

    def test_resume_after_later_fragment_failure_submits_only_the_incomplete_fragment(self) -> None:
        source = self.root / "source.epub"
        _write_epub_fixture(source)
        checkpoint_store = self._checkpoint_store("later-failure")
        first_provider = _ScriptedProvider(
            responses=(
                {
                    _FRAGMENT_IDS[0]: "Cau thu nhat.",
                    _FRAGMENT_IDS[1]: "Cau thu hai.",
                },
                RuntimeError("offline later-fragment failure"),
            )
        )

        with self.assertRaisesRegex(RuntimeError, "later-fragment failure"):
            self._workflow(first_provider, checkpoint_store).translate(
                {"sourcePath": str(source)},
                source_language="en",
                target_language="vi",
            )

        resumed_provider = _ScriptedProvider(
            responses=({_FRAGMENT_IDS[2]: "Cau thu ba."},)
        )
        result = self._workflow(resumed_provider, checkpoint_store).translate(
            {"sourcePath": str(source)},
            source_language="en",
            target_language="vi",
        )

        self.assertEqual(_request_unit_ids(first_provider.calls), [_FRAGMENT_IDS[:2], _FRAGMENT_IDS[2:]])
        self.assertEqual(_request_unit_ids(resumed_provider.calls), [_FRAGMENT_IDS[2:]])
        self.assertEqual(_context_unit_ids(resumed_provider.calls), [_FRAGMENT_IDS[1:2]])
        self.assertEqual(
            [unit.translated_text for unit in result.translation.units],
            ["Cau thu nhat.", "Cau thu hai.", "Cau thu ba."],
        )

    def test_cancellation_after_a_completed_fragment_window_resumes_safely(self) -> None:
        source = self.root / "source.epub"
        _write_epub_fixture(source)
        checkpoint_store = self._checkpoint_store("cancelled-window")
        cancellation = CancellationToken()
        cancelling_provider = _ScriptedProvider(
            responses=(
                {
                    _FRAGMENT_IDS[0]: "Cau thu nhat.",
                    _FRAGMENT_IDS[1]: "Cau thu hai.",
                },
            ),
            after_call=lambda _: cancellation._cancel(),
        )

        with self.assertRaises(JobCancelled):
            self._workflow(cancelling_provider, checkpoint_store).translate(
                {"sourcePath": str(source)},
                source_language="en",
                target_language="vi",
                cancellation=cancellation,
            )

        resumed_provider = _ScriptedProvider(
            responses=({_FRAGMENT_IDS[2]: "Cau thu ba."},)
        )
        result = self._workflow(resumed_provider, checkpoint_store).translate(
            {"sourcePath": str(source)},
            source_language="en",
            target_language="vi",
        )

        self.assertEqual(_request_unit_ids(cancelling_provider.calls), [_FRAGMENT_IDS[:2]])
        self.assertEqual(_request_unit_ids(resumed_provider.calls), [_FRAGMENT_IDS[2:]])
        self.assertEqual(_context_unit_ids(resumed_provider.calls), [_FRAGMENT_IDS[1:2]])
        self.assertEqual(
            [unit.translated_text for unit in result.translation.units],
            ["Cau thu nhat.", "Cau thu hai.", "Cau thu ba."],
        )

    def _checkpoint_store(self, namespace: str) -> EpubTranslationCheckpointStore:
        return EpubTranslationCheckpointStore(self.root / "artifacts", namespace)

    @staticmethod
    def _workflow(
        provider: LlmProvider,
        checkpoint_store: EpubTranslationCheckpointStore,
    ) -> EpubTranslationWorkflow:
        policy = EpubTranslationBatchingPolicy(max_units_per_window=2, overlap_units=1)
        return EpubTranslationWorkflow(
            TranslationService(
                provider,
                max_units_per_window=policy.max_units_per_window,
                overlap_units=policy.overlap_units,
            ),
            checkpoint_store,
            context_window_builder=EpubChapterContextWindowBuilder(policy),
        )


class _ScriptedProvider(LlmProvider):
    def __init__(
        self,
        *,
        responses: tuple[dict[str, str] | Exception, ...],
        after_call: Callable[[int], None] | None = None,
    ) -> None:
        self._responses = iter(responses)
        self._after_call = after_call
        self.calls: list[TranslationRequest] = []

    @property
    def capabilities(self) -> LlmProviderCapabilities:
        return LlmProviderCapabilities(
            model_ids=("offline-test-model",),
            context_window_tokens=8_192,
            supports_structured_output=True,
            supports_streaming=False,
        )

    def translate(self, request: TranslationRequest, instructions: str) -> TranslationArtifact:
        del instructions
        self.calls.append(request)
        response = next(self._responses)
        if self._after_call is not None:
            self._after_call(len(self.calls))
        if isinstance(response, Exception):
            raise response
        return TranslationArtifact(
            target_language=request.target_language,
            units=tuple(
                TranslatedTextUnit(unit.unit_id, response[unit.unit_id])
                for unit in request.artifact.units
            ),
        )


def _request_unit_ids(requests: list[TranslationRequest]) -> list[tuple[str, ...]]:
    return [tuple(unit.unit_id for unit in request.artifact.units) for request in requests]


def _context_unit_ids(requests: list[TranslationRequest]) -> list[tuple[str, ...]]:
    return [
        () if request.context is None else tuple(unit.unit_id for unit in request.context.units)
        for request in requests
    ]


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


def _fragment_source() -> str:
    first = (
        "First sentence carries enough ordinary prose to exercise a deterministic EPUB "
        "translation boundary without inline markup or unusual punctuation."
    )
    second = (
        "Second sentence preserves original spacing after the previous sentence while "
        "remaining ordinary prose for this offline fixture."
    )
    third = (
        "Third sentence completes the long paragraph with more ordinary prose so the "
        "conservative policy can safely create a final fragment."
    )
    return f"{first}  {second}\n{third}"


def _write_epub_fixture(path: Path) -> None:
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
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
            f'<p id="start">{_fragment_source()}</p>'
            "</body></html>",
        )
        archive.writestr("OEBPS/book.css", b"p { color: #123456; }")
        archive.writestr("OEBPS/images/cover.jpg", b"image-bytes")
        archive.writestr("OEBPS/fonts/book.otf", b"font-bytes")
