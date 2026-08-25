"""Concrete EPUB translation composition before EPUB merge and rebuilding.

The workflow owns the EPUB stage sequence: acquire a selected EPUB path,
inspect its package, project its translatable text, and translate that
projection. ``TranslationService`` owns the source-neutral context, provider
call, retry, and validation work. Merge/checkpoint/rebuild/export are later
EPUB workflow stages and deliberately do not appear here.
"""

from __future__ import annotations

from dataclasses import dataclass

from mint_lingo_engine.epub.document import (
    EpubDocumentArtifact,
    EpubPackageValidationError,
)
from mint_lingo_engine.epub.inspection import EpubPackageInspector
from mint_lingo_engine.epub.projection import (
    EpubStructuredTextProjection,
    EpubStructuredTextProjector,
)
from mint_lingo_engine.epub.source import EpubSourceAcquisition
from mint_lingo_engine.translation.models import TranslationArtifact, TranslationRequest
from mint_lingo_engine.translation.service import TranslationService
from mint_lingo_engine.translation.validation import validate_translation_artifact


@dataclass(frozen=True)
class EpubTranslationWorkflowResult:
    """EPUB-owned inputs and the validated, provider-neutral translation result.

    ``document`` and ``projection`` retain EPUB package and merge-target data
    within the EPUB workflow boundary. ``translation`` is the shared result
    that a later EPUB-only merge stage will consume by stable ID.
    """

    document: EpubDocumentArtifact
    projection: EpubStructuredTextProjection
    translation: TranslationArtifact

    def __post_init__(self) -> None:
        if not isinstance(self.document, EpubDocumentArtifact):
            raise TypeError("document must be an EpubDocumentArtifact")
        if not isinstance(self.projection, EpubStructuredTextProjection):
            raise TypeError("projection must be an EpubStructuredTextProjection")
        if not isinstance(self.translation, TranslationArtifact):
            raise TypeError("translation must be a TranslationArtifact")


class EpubTranslationWorkflow:
    """Compose the concrete EPUB translation stages in their required order.

    The caller supplies a configured ``TranslationService``. This makes model
    selection explicit at the composition boundary while keeping model IDs,
    provider payloads, and provider implementations out of the EPUB workflow.
    The shared service constructs translation context and uses its supplied
    ``LlmProvider``; this workflow neither selects nor discovers a model.
    """

    def __init__(
        self,
        translation_service: TranslationService,
        *,
        source_acquisition: EpubSourceAcquisition | None = None,
        package_inspector: EpubPackageInspector | None = None,
        text_projector: EpubStructuredTextProjector | None = None,
    ) -> None:
        if not isinstance(translation_service, TranslationService):
            raise TypeError("translation_service must be a TranslationService")
        if source_acquisition is not None and not isinstance(
            source_acquisition, EpubSourceAcquisition
        ):
            raise TypeError("source_acquisition must be an EpubSourceAcquisition")
        if package_inspector is not None and not isinstance(
            package_inspector, EpubPackageInspector
        ):
            raise TypeError("package_inspector must be an EpubPackageInspector")
        if text_projector is not None and not isinstance(
            text_projector, EpubStructuredTextProjector
        ):
            raise TypeError("text_projector must be an EpubStructuredTextProjector")

        self._translation_service = translation_service
        self._source_acquisition = source_acquisition or EpubSourceAcquisition()
        self._package_inspector = package_inspector or EpubPackageInspector()
        self._text_projector = text_projector or EpubStructuredTextProjector()

    def translate(
        self,
        source_payload: object,
        *,
        source_language: str,
        target_language: str,
    ) -> EpubTranslationWorkflowResult | EpubPackageValidationError:
        """Run EPUB acquisition, inspection, projection, translation, validation.

        Package validation failures return the existing EPUB-owned error. A
        provider result that fails shared validation is handled by the supplied
        ``TranslationService`` and raises its existing normalized service error.
        """

        source = self._source_acquisition.accept(source_payload)
        inspected = self._package_inspector.inspect(source)
        if isinstance(inspected, EpubPackageValidationError):
            return inspected

        projection = self._text_projector.project(inspected, source_language)
        translation = self._translation_service.translate(
            projection.structured_text,
            target_language,
        )
        validation = validate_translation_artifact(
            TranslationRequest(projection.structured_text, target_language),
            translation,
        )
        if not isinstance(validation, TranslationArtifact):
            raise AssertionError("TranslationService returned an invalid translation")

        return EpubTranslationWorkflowResult(
            document=inspected,
            projection=projection,
            translation=validation,
        )
