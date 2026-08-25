import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
import zipfile

from mint_lingo_engine.epub_document import EpubPackageValidationError
from mint_lingo_engine.epub_translation_workflow import EpubTranslationWorkflow
from mint_lingo_engine.llm_provider import LlmProvider, LlmProviderCapabilities
from mint_lingo_engine.translation import (
    TranslatedTextUnit,
    TranslationArtifact,
    TranslationRequest,
)
from mint_lingo_engine.translation_service import TranslationService


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
            )
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

    def test_returns_epub_owned_package_error_without_calling_provider(self) -> None:
        provider = _FakeLlmProvider(responses=())
        workflow = EpubTranslationWorkflow(
            TranslationService(provider, max_units_per_window=1)
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
            TranslationService(provider, max_units_per_window=2)
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


class _FakeLlmProvider(LlmProvider):
    def __init__(self, *, responses: tuple[TranslationArtifact, ...]) -> None:
        self._responses = iter(responses)
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
        return next(self._responses)


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
