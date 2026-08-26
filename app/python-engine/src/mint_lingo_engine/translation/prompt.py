"""Provider-neutral instructions for structured translation requests."""

from __future__ import annotations

import json

from mint_lingo_engine.translation.models import TranslationRequest


_MODEL_FACING_LANGUAGE_NAMES = {
    "en": "English",
    "vi": "Vietnamese",
    "ja": "Japanese",
    "ko": "Korean",
    "zh-Hans": "Chinese (Simplified)",
    "zh-Hant": "Chinese (Traditional)",
    "pt-BR": "Portuguese (Brazil)",
    "pt-PT": "Portuguese (Portugal)",
    "fr": "French",
    "de": "German",
    "es": "Spanish",
    "it": "Italian",
    "ru": "Russian",
    "hi": "Hindi",
    "ar": "Arabic",
    "th": "Thai",
    "id": "Indonesian",
}


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
    target_language_name = _MODEL_FACING_LANGUAGE_NAMES.get(
        request.target_language,
        request.target_language,
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
            (
                "Target language: "
                f"{target_language_name} ({request.target_language})"
            ),
            (
                "Write all translated natural-language text in "
                f"{target_language_name}."
            ),
            "Do not use a different language for translated natural-language text.",
            (
                "Preserve text in another language or script only when it is a "
                "proper name, quotation, code, or explicitly non-translatable."
            ),
            "Return one translated text value for every required unit ID.",
            "Preserve each required unit ID exactly and return no other unit IDs.",
            f"Required unit IDs, in order: {required_unit_ids}",
            context_instruction,
        )
    )
