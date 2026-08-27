"""Concrete EPUB translation composition through in-memory package rebuilding.

The workflow owns the EPUB stage sequence: acquire a selected EPUB path,
inspect its package, project its translatable text, translate that projection,
restore XHTML, and rebuild an in-memory package. ``TranslationService`` owns
the source-neutral context, provider call, retry, and validation work.
Validation and destination export remain later EPUB workflow stages.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

from mint_lingo_engine.epub.document import (
    EpubDocumentArtifact,
    EpubPackageValidationError,
)
from mint_lingo_engine.epub.builder import (
    EpubPackageBuilder,
    EpubRebuiltPackageArtifact,
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
from mint_lingo_engine.epub.chapter_context import EpubChapterContextWindowBuilder
from mint_lingo_engine.epub.translation_guard import (
    reject_oversized_epub_translation_units,
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
    stable-ID and XHTML-restoration results, while ``rebuilt_package`` holds
    the in-memory package for a later validation/export stage.
    """

    document: EpubDocumentArtifact
    projection: EpubStructuredTextProjection
    translation: TranslationArtifact
    merged_translation: EpubMergedTranslationArtifact
    restored_document: EpubRestoredDocumentArtifact
    rebuilt_package: EpubRebuiltPackageArtifact

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
        if not isinstance(self.rebuilt_package, EpubRebuiltPackageArtifact):
            raise TypeError("rebuilt_package must be an EpubRebuiltPackageArtifact")


class EpubTranslationWorkflow:
    """Compose the concrete EPUB translation and package-build stages.

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
        package_builder: EpubPackageBuilder | None = None,
        context_window_builder: EpubChapterContextWindowBuilder | None = None,
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
        if package_builder is not None and not isinstance(package_builder, EpubPackageBuilder):
            raise TypeError("package_builder must be an EpubPackageBuilder")
        if context_window_builder is not None and not isinstance(
            context_window_builder,
            EpubChapterContextWindowBuilder,
        ):
            raise TypeError("context_window_builder must be an EpubChapterContextWindowBuilder")

        self._translation_service = translation_service
        self._checkpoint_store = checkpoint_store
        self._source_acquisition = source_acquisition or EpubSourceAcquisition()
        self._package_inspector = package_inspector or EpubPackageInspector()
        self._text_projector = text_projector or EpubStructuredTextProjector()
        self._document_restorer = document_restorer or EpubDocumentRestorer()
        self._package_builder = package_builder or EpubPackageBuilder()
        self._context_window_builder = context_window_builder

    def translate(
        self,
        source_payload: object,
        *,
        source_language: str,
        target_language: str,
        cancellation: CancellationToken | None = None,
        on_translation_progress: Callable[[int, int], None] | None = None,
    ) -> EpubTranslationWorkflowResult | EpubPackageValidationError:
        """Run EPUB acquisition, translation, restoration, and package rebuilding.

        Package validation failures return the existing EPUB-owned error. A
        provider result that fails shared validation is handled by the supplied
        ``TranslationService`` and raises its existing normalized service error.
        """

        if cancellation is not None and not isinstance(cancellation, CancellationToken):
            raise TypeError("cancellation must be a CancellationToken or None")
        if on_translation_progress is not None and not callable(on_translation_progress):
            raise TypeError("on_translation_progress must be callable or None")
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
        total_units = len(projection.structured_text.units)
        if on_translation_progress is not None and total_units:
            on_translation_progress(len(translated_by_id), total_units)
        pending_units = tuple(
            unit
            for unit in projection.structured_text.units
            if unit.unit_id not in translated_by_id
        )
        if pending_units:
            reject_oversized_epub_translation_units(pending_units)
            pending_artifact = StructuredTextArtifact(
                source_language=projection.structured_text.source_language,
                units=pending_units,
            )
            pending_translation = self._translation_service.translate(
                pending_artifact,
                target_language,
                request_windows=(
                    self._context_window_builder.build(
                        projection,
                        target_language,
                        requested_unit_ids=frozenset(unit.unit_id for unit in pending_units),
                    )
                    if self._context_window_builder is not None
                    else None
                ),
                on_request_translated=self._checkpoint_and_observe_cancellation(
                    cancellation,
                    completed_unit_ids=set(translated_by_id),
                    total_units=total_units,
                    on_translation_progress=on_translation_progress,
                ),
                before_provider_attempt=(
                    cancellation.raise_if_cancelled
                    if cancellation is not None
                    else None
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
        restored_document = self._document_restorer.restore(
            inspected,
            merged_translation,
        )
        return EpubTranslationWorkflowResult(
            document=inspected,
            projection=projection,
            translation=validation,
            merged_translation=merged_translation,
            restored_document=restored_document,
            rebuilt_package=self._package_builder.build(restored_document),
        )

    def _checkpoint_and_observe_cancellation(
        self,
        cancellation: CancellationToken | None,
        *,
        completed_unit_ids: set[str],
        total_units: int,
        on_translation_progress: Callable[[int, int], None] | None,
    ) -> Callable[[TranslationRequest, TranslationArtifact], None]:
        def on_request_translated(
            request: TranslationRequest,
            translation: TranslationArtifact,
        ) -> None:
            self._checkpoint_store.record(request, translation)
            if cancellation is not None:
                cancellation.raise_if_cancelled()
            completed_unit_ids.update(unit.unit_id for unit in translation.units)
            if on_translation_progress is not None:
                on_translation_progress(len(completed_unit_ids), total_units)

        return on_request_translated
