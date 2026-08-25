"""Provider-neutral instructions for structured translation requests."""

from __future__ import annotations

import json

from mint_lingo_engine.translation import TranslationRequest


def build_structured_translation_instructions(request: TranslationRequest) -> str:
    """Describe the target language and exact translation-result obligations.

    The instructions deliberately contain no source-format assumptions or
    vendor payload syntax. Provider adapters remain responsible for placing
    these instructions and request content into a concrete provider call.
    """

    if not isinstance(request, TranslationRequest):
        raise TypeError("request must be a TranslationRequest")

    required_unit_ids = json.dumps(
        [unit.unit_id for unit in request.artifact.units],
        ensure_ascii=False,
    )
    context_instruction = (
        "Reference context is supplied only for comprehension; do not return "
        "translations for reference-context units."
        if request.context is not None
        else "No reference context is supplied."
    )
    return "\n".join(
        (
            "Translate the requested source units.",
            f"Source language: {request.artifact.source_language}",
            f"Target language: {request.target_language}",
            "Return one translated text value for every required unit ID.",
            "Preserve each required unit ID exactly and return no other unit IDs.",
            f"Required unit IDs, in order: {required_unit_ids}",
            context_instruction,
        )
    )
