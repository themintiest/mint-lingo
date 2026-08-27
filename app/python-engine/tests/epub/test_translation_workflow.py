from collections.abc import Callable
from io import BytesIO
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
import zipfile

from mint_lingo_engine.epub.document import EpubPackageValidationError
from mint_lingo_engine.epub.translation_checkpoint import (
    EpubTranslationCheckpointStore,
)
from mint_lingo_engine.epub.translation_workflow import EpubTranslationWorkflow
from mint_lingo_engine.processing.runner import CancellationToken, JobCancelled
from mint_lingo_engine.providers.translation.base import (
    LlmProvider,
    LlmProviderCapabilities,
    LlmProviderResponseError,
    LlmProviderResponseFailureCode,
)
from mint_lingo_engine.translation.models import (
    StructuredTextArtifact,
    StructuredTextUnit,
    TranslatedTextUnit,
    TranslationArtifact,
    TranslationRequest,
)
from mint_lingo_engine.translation.service import TranslationService


class EpubTranslationWorkflowTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(self.enterContext(TemporaryDirectory()))

    def test_composes_epub_stages_with_shared_context_and_validation(self) -> None:
        book_path = self.root / "book.epub"
        _write_epub(book_path)
        provider = _FakeLlmProvider(
            responses=(
                _translation("vi", ("chapter.text.1", "Mot")),
                _translation("vi", ("chapter.text.2", "Hai")),
            )
        )
        workflow = EpubTranslationWorkflow(
            TranslationService(
                provider,
                max_units_per_window=1,
                overlap_units=1,
            ),
            self._checkpoint_store(),
        )

        result = workflow.translate(
            {"sourcePath": str(book_path)},
            source_language="en",
            target_language="vi",
        )

        self.assertNotIsInstance(result, EpubPackageValidationError)
        assert not isinstance(result, EpubPackageValidationError)
        self.assertEqual(result.document.package_metadata.title, "Source book")
        self.assertEqual(
            [(unit.unit_id, unit.text) for unit in result.projection.structured_text.units],
            [("chapter.text.1", "First"), ("chapter.text.2", "Second")],
        )
        self.assertEqual(
            [(unit.unit_id, unit.translated_text) for unit in result.translation.units],
            [("chapter.text.1", "Mot"), ("chapter.text.2", "Hai")],
        )
        self.assertEqual(
            [[unit.unit_id for unit in request.artifact.units] for request in provider.calls],
            [["chapter.text.1"], ["chapter.text.2"]],
        )
        self.assertEqual(
            [
                [] if request.context is None else [unit.unit_id for unit in request.context.units]
                for request in provider.calls
            ],
            [["chapter.text.2"], ["chapter.text.1"]],
        )
        self.assertEqual(
            [
                (unit.target.target_id, unit.target.manifest_item_id, unit.translated_text)
                for unit in result.merged_translation.units
            ],
            [
                ("chapter.text.1", "chapter", "Mot"),
                ("chapter.text.2", "chapter", "Hai"),
            ],
        )
        self.assertEqual(result.restored_document.package_metadata.language, "vi")
        self.assertIn("<p>Mot</p><p>Hai</p>", result.restored_document.xhtml_documents[0].serialized_xhtml)
        assert result.restored_document.navigation_document is not None
        self.assertIn('lang="vi"', result.restored_document.navigation_document.serialized_xhtml)
        with zipfile.ZipFile(BytesIO(result.rebuilt_package.package_bytes)) as rebuilt:
            self.assertEqual(
                rebuilt.read("OEBPS/chapter.xhtml"),
                b'<html lang="vi"><body><p>Mot</p><p>Hai</p></body></html>',
            )

    def test_returns_epub_owned_package_error_without_calling_provider(self) -> None:
        provider = _FakeLlmProvider(responses=())
        workflow = EpubTranslationWorkflow(
            TranslationService(provider, max_units_per_window=1),
            self._checkpoint_store(),
        )

        result = workflow.translate(
            {"sourcePath": str(self.root / "missing.epub")},
            source_language="en",
            target_language="vi",
        )

        self.assertIsInstance(result, EpubPackageValidationError)
        self.assertEqual(provider.calls, [])

    def test_uses_shared_validation_to_retry_only_the_missing_epub_unit(self) -> None:
        book_path = self.root / "book.epub"
        _write_epub(book_path)
        provider = _FakeLlmProvider(
            responses=(
                _translation("vi", ("chapter.text.1", "Mot")),
                _translation("vi", ("chapter.text.2", "Hai")),
            )
        )
        workflow = EpubTranslationWorkflow(
            TranslationService(provider, max_units_per_window=2),
            self._checkpoint_store(),
        )

        result = workflow.translate(
            {"sourcePath": str(book_path)},
            source_language="en",
            target_language="vi",
        )

        self.assertNotIsInstance(result, EpubPackageValidationError)
        assert not isinstance(result, EpubPackageValidationError)
        self.assertEqual(
            [(unit.unit_id, unit.translated_text) for unit in result.translation.units],
            [("chapter.text.1", "Mot"), ("chapter.text.2", "Hai")],
        )
        self.assertEqual(
            [[unit.unit_id for unit in request.artifact.units] for request in provider.calls],
            [["chapter.text.1", "chapter.text.2"], ["chapter.text.2"]],
        )

    def test_resumes_from_completed_unit_checkpoints_after_a_provider_failure(self) -> None:
        book_path = self.root / "book.epub"
        _write_epub(book_path)
        checkpoint_store = self._checkpoint_store()
        first_provider = _FakeLlmProvider(
            responses=(
                _translation("vi", ("chapter.text.1", "Mot")),
                RuntimeError("simulated provider failure"),
            )
        )
        first_workflow = EpubTranslationWorkflow(
            TranslationService(first_provider, max_units_per_window=1),
            checkpoint_store,
        )

        with self.assertRaisesRegex(RuntimeError, "simulated provider failure"):
            first_workflow.translate(
                {"sourcePath": str(book_path)},
                source_language="en",
                target_language="vi",
            )

        resumed_provider = _FakeLlmProvider(
            responses=(_translation("vi", ("chapter.text.2", "Hai")),)
        )
        progress: list[tuple[int, int]] = []
        result = EpubTranslationWorkflow(
            TranslationService(resumed_provider, max_units_per_window=1),
            checkpoint_store,
        ).translate(
            {"sourcePath": str(book_path)},
            source_language="en",
            target_language="vi",
            on_translation_progress=lambda completed, total: progress.append(
                (completed, total)
            ),
        )

        self.assertNotIsInstance(result, EpubPackageValidationError)
        assert not isinstance(result, EpubPackageValidationError)
        self.assertEqual(
            [(unit.unit_id, unit.translated_text) for unit in result.translation.units],
            [("chapter.text.1", "Mot"), ("chapter.text.2", "Hai")],
        )
        self.assertEqual(
            [[unit.unit_id for unit in request.artifact.units] for request in resumed_provider.calls],
            [["chapter.text.2"]],
        )
        self.assertEqual(progress, [(1, 2), (2, 2)])

    def test_checkpoints_a_completed_unit_before_observed_cancellation(self) -> None:
        book_path = self.root / "book.epub"
        _write_epub(book_path)
        checkpoint_store = self._checkpoint_store()
        cancellation = CancellationToken()
        cancelling_provider = _FakeLlmProvider(
            responses=(
                _translation("vi", ("chapter.text.1", "Mot")),
                _translation("vi", ("chapter.text.2", "Hai")),
            ),
            after_call=lambda call_count: cancellation._cancel()
            if call_count == 1
            else None,
        )
        workflow = EpubTranslationWorkflow(
            TranslationService(cancelling_provider, max_units_per_window=1),
            checkpoint_store,
        )

        with self.assertRaises(JobCancelled):
            workflow.translate(
                {"sourcePath": str(book_path)},
                source_language="en",
                target_language="vi",
                cancellation=cancellation,
            )

        resumed_provider = _FakeLlmProvider(
            responses=(_translation("vi", ("chapter.text.2", "Hai")),)
        )
        result = EpubTranslationWorkflow(
            TranslationService(resumed_provider, max_units_per_window=1),
            checkpoint_store,
        ).translate(
            {"sourcePath": str(book_path)},
            source_language="en",
            target_language="vi",
        )

        self.assertNotIsInstance(result, EpubPackageValidationError)
        assert not isinstance(result, EpubPackageValidationError)
        self.assertEqual(
            [[unit.unit_id for unit in request.artifact.units] for request in resumed_provider.calls],
            [["chapter.text.2"]],
        )

    def test_cancels_before_retrying_a_malformed_provider_response(self) -> None:
        book_path = self.root / "book.epub"
        _write_epub(book_path)
        checkpoint_store = self._checkpoint_store()
        cancellation = CancellationToken()
        provider = _FakeLlmProvider(
            responses=(
                _translation("vi", ("chapter.text.1", "Mot")),
                _retryable_malformed_response(),
            ),
            after_call=lambda call_count: cancellation._cancel()
            if call_count == 2
            else None,
        )
        workflow = EpubTranslationWorkflow(
            TranslationService(provider, max_units_per_window=1),
            checkpoint_store,
        )

        with self.assertRaises(JobCancelled):
            workflow.translate(
                {"sourcePath": str(book_path)},
                source_language="en",
                target_language="vi",
                cancellation=cancellation,
            )

        self.assertEqual(len(provider.calls), 2)
        resumed_provider = _FakeLlmProvider(
            responses=(_translation("vi", ("chapter.text.2", "Hai")),)
        )
        result = EpubTranslationWorkflow(
            TranslationService(resumed_provider, max_units_per_window=1),
            checkpoint_store,
        ).translate(
            {"sourcePath": str(book_path)},
            source_language="en",
            target_language="vi",
        )

        self.assertNotIsInstance(result, EpubPackageValidationError)
        self.assertEqual(
            [[unit.unit_id for unit in request.artifact.units] for request in resumed_provider.calls],
            [["chapter.text.2"]],
        )

    def test_rejects_a_checkpoint_when_its_source_text_no_longer_matches(self) -> None:
        checkpoint_store = self._checkpoint_store()
        original = StructuredTextArtifact(
            source_language="en",
            units=(StructuredTextUnit("chapter.text.1", "First"),),
        )
        checkpoint_store.record(
            TranslationRequest(original, "vi"),
            _translation("vi", ("chapter.text.1", "Mot")),
        )
        changed = StructuredTextArtifact(
            source_language="en",
            units=(StructuredTextUnit("chapter.text.1", "Revised first"),),
        )

        with self.assertRaisesRegex(ValueError, "does not match"):
            checkpoint_store.load_completed(changed, "vi")

    def _checkpoint_store(self) -> EpubTranslationCheckpointStore:
        return EpubTranslationCheckpointStore(
            self.root / "project" / "artifacts",
            checkpoint_namespace="book-translation",
        )


class _FakeLlmProvider(LlmProvider):
    def __init__(
        self,
        *,
        responses: tuple[TranslationArtifact | Exception, ...],
        after_call: Callable[[int], None] | None = None,
    ) -> None:
        self._responses = iter(responses)
        self._after_call = after_call
        self.calls: list[TranslationRequest] = []

    @property
    def capabilities(self) -> LlmProviderCapabilities:
        return LlmProviderCapabilities(
            model_ids=("configured-offline-model",),
            context_window_tokens=None,
            supports_structured_output=True,
            supports_streaming=False,
        )

    def translate(
        self,
        request: TranslationRequest,
        instructions: str,
    ) -> TranslationArtifact:
        self.calls.append(request)
        response = next(self._responses)
        if self._after_call is not None:
            self._after_call(len(self.calls))
        if isinstance(response, Exception):
            raise response
        return response


def _translation(
    target_language: str,
    *units: tuple[str, str],
) -> TranslationArtifact:
    return TranslationArtifact(
        target_language=target_language,
        units=tuple(
            TranslatedTextUnit(unit_id=unit_id, translated_text=translated_text)
            for unit_id, translated_text in units
        ),
    )


def _retryable_malformed_response() -> LlmProviderResponseError:
    return LlmProviderResponseError(
        LlmProviderResponseFailureCode.MALFORMED_RESPONSE,
        retryable=True,
    )


def _write_epub(path: Path) -> None:
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
            '<package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata><dc:title>Source book</dc:title></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>',
        )
        archive.writestr(
            "OEBPS/chapter.xhtml",
            "<html><body><p>First</p><p>Second</p></body></html>",
        )
        archive.writestr("OEBPS/nav.xhtml", "<html><body><nav/></body></html>")
