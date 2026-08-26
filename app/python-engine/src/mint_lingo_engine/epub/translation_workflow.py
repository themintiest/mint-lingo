"""Concrete EPUB translation composition before EPUB rebuilding.

The workflow owns the EPUB stage sequence: acquire a selected EPUB path,
inspect its package, project its translatable text, and translate that
projection. ``TranslationService`` owns the source-neutral context, provider
call, retry, and validation work. This workflow checkpoints completed EPUB
units and pairs results with EPUB-owned merge targets; XHTML restoration,
rebuilding, and export remain later EPUB workflow stages.
"""

from __future__ import annotations

from collections.abc import Callable
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
from mint_lingo_engine.epub.restoration import (
    EpubDocumentRestorer,
    EpubRestoredDocumentArtifact,
)
from mint_lingo_engine.epub.source import EpubSourceAcquisition
from mint_lingo_engine.epub.translation_checkpoint import (
    EpubTranslationCheckpointStore,
)
from mint_lingo_engine.epub.translation_merge import (
    EpubMergedTranslationArtifact,
    merge_translation_artifact,
)
from mint_lingo_engine.processing.runner import CancellationToken
from mint_lingo_engine.translation.models import (
    StructuredTextArtifact,
    TranslationArtifact,
    TranslationRequest,
)
from mint_lingo_engine.translation.service import TranslationService
from mint_lingo_engine.translation.validation import validate_translation_artifact


@dataclass(frozen=True)
class EpubTranslationWorkflowResult:
    """EPUB-owned inputs and the validated, provider-neutral translation result.

    ``document`` and ``projection`` retain EPUB package and merge-target data
    within the EPUB workflow boundary. ``translation`` remains shared, while
    ``merged_translation`` and ``restored_document`` retain the EPUB-only
    stable-ID and XHTML-restoration results for a later package builder.
    """

    document: EpubDocumentArtifact
    projection: EpubStructuredTextProjection
    translation: TranslationArtifact
    merged_translation: EpubMergedTranslationArtifact
    restored_document: EpubRestoredDocumentArtifact

    def __post_init__(self) -> None:
        if not isinstance(self.document, EpubDocumentArtifact):
            raise TypeError("document must be an EpubDocumentArtifact")
        if not isinstance(self.projection, EpubStructuredTextProjection):
            raise TypeError("projection must be an EpubStructuredTextProjection")
        if not isinstance(self.translation, TranslationArtifact):
            raise TypeError("translation must be a TranslationArtifact")
        if not isinstance(self.merged_translation, EpubMergedTranslationArtifact):
            raise TypeError("merged_translation must be an EpubMergedTranslationArtifact")
        if not isinstance(self.restored_document, EpubRestoredDocumentArtifact):
            raise TypeError("restored_document must be an EpubRestoredDocumentArtifact")


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
        checkpoint_store: EpubTranslationCheckpointStore,
        *,
        source_acquisition: EpubSourceAcquisition | None = None,
        package_inspector: EpubPackageInspector | None = None,
        text_projector: EpubStructuredTextProjector | None = None,
        document_restorer: EpubDocumentRestorer | None = None,
    ) -> None:
        if not isinstance(translation_service, TranslationService):
            raise TypeError("translation_service must be a TranslationService")
        if not isinstance(checkpoint_store, EpubTranslationCheckpointStore):
            raise TypeError("checkpoint_store must be an EpubTranslationCheckpointStore")
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
        if document_restorer is not None and not isinstance(
            document_restorer, EpubDocumentRestorer
        ):
            raise TypeError("document_restorer must be an EpubDocumentRestorer")

        self._translation_service = translation_service
        self._checkpoint_store = checkpoint_store
        self._source_acquisition = source_acquisition or EpubSourceAcquisition()
        self._package_inspector = package_inspector or EpubPackageInspector()
        self._text_projector = text_projector or EpubStructuredTextProjector()
        self._document_restorer = document_restorer or EpubDocumentRestorer()

    def translate(
        self,
        source_payload: object,
        *,
        source_language: str,
        target_language: str,
        cancellation: CancellationToken | None = None,
    ) -> EpubTranslationWorkflowResult | EpubPackageValidationError:
        """Run EPUB acquisition, inspection, translation, merge, and restoration.

        Package validation failures return the existing EPUB-owned error. A
        provider result that fails shared validation is handled by the supplied
        ``TranslationService`` and raises its existing normalized service error.
        """

        if cancellation is not None and not isinstance(cancellation, CancellationToken):
            raise TypeError("cancellation must be a CancellationToken or None")
        if cancellation is not None:
            cancellation.raise_if_cancelled()

        source = self._source_acquisition.accept(source_payload)
        inspected = self._package_inspector.inspect(source)
        if isinstance(inspected, EpubPackageValidationError):
            return inspected

        projection = self._text_projector.project(inspected, source_language)
        completed = self._checkpoint_store.load_completed(
            projection.structured_text,
            target_language,
        )
        translated_by_id = {unit.unit_id: unit for unit in completed.units}
        pending_units = tuple(
            unit
            for unit in projection.structured_text.units
            if unit.unit_id not in translated_by_id
        )
        if pending_units:
            pending_artifact = StructuredTextArtifact(
                source_language=projection.structured_text.source_language,
                units=pending_units,
            )
            pending_translation = self._translation_service.translate(
                pending_artifact,
                target_language,
                on_request_translated=self._checkpoint_and_observe_cancellation(
                    cancellation
                ),
            )
            translated_by_id.update(
                {unit.unit_id: unit for unit in pending_translation.units}
            )
        translation = TranslationArtifact(
            target_language=target_language,
            units=tuple(
                translated_by_id[unit.unit_id]
                for unit in projection.structured_text.units
            ),
        )
        validation = validate_translation_artifact(
            TranslationRequest(projection.structured_text, target_language),
            translation,
        )
        if not isinstance(validation, TranslationArtifact):
            raise AssertionError("TranslationService returned an invalid translation")

        merged_translation = merge_translation_artifact(projection, validation)
        return EpubTranslationWorkflowResult(
            document=inspected,
            projection=projection,
            translation=validation,
            merged_translation=merged_translation,
            restored_document=self._document_restorer.restore(
                inspected,
                merged_translation,
            ),
        )

    def _checkpoint_and_observe_cancellation(
        self,
        cancellation: CancellationToken | None,
    ) -> Callable[[TranslationRequest, TranslationArtifact], None]:
        def on_request_translated(
            request: TranslationRequest,
            translation: TranslationArtifact,
        ) -> None:
            self._checkpoint_store.record(request, translation)
            if cancellation is not None:
                cancellation.raise_if_cancelled()

        return on_request_translated
