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
        (
            "Reference context is supplied only for comprehension and for "
            "maintaining consistent meaning, tone, terminology, names, and "
            "relationships. Do not translate or return reference-context units."
        )
        if request.context is not None
        else "No reference context is supplied."
    )

    return "\n".join(
        (
            "You are a translation engine.",
            "Translate only the requested source units.",
            f"Source language: {request.artifact.source_language}",
            (
                "Target language: "
                f"{target_language_name} ({request.target_language})"
            ),
            (
                "Write all translated natural-language text in "
                f"{target_language_name}."
            ),
            (
                "Do not use a different language for translated "
                "natural-language text."
            ),
            (
                "Preserve text in another language or script only when it is a "
                "proper name, quotation, code, identifier, or explicitly "
                "non-translatable."
            ),
            (
                "Translate the complete text of every requested unit from "
                "beginning to end."
            ),
            (
                "A requested unit may contain multiple sentences. Translate "
                "every sentence and every meaningful part of its text."
            ),
            (
                "Do not omit any sentence, clause, dialogue, quotation, or "
                "other meaningful portion of a requested unit."
            ),
            (
                "Preserve the meaning, tone, intent, narrative perspective, "
                "and level of formality of the source."
            ),
            (
                "Preserve names, terminology, quotations, and relationships "
                "consistently when the supplied context makes them clear."
            ),
            (
                "Do not summarize, shorten, expand, explain, censor, rewrite, "
                "or add information that is not present in the source."
            ),
            (
                "Return exactly one translated text value for every required "
                "unit ID."
            ),
            "Preserve each required unit ID exactly.",
            "Preserve the required unit order.",
            "Do not omit, merge, split, duplicate, or invent units.",
            "Return no unit IDs other than the required unit IDs.",
            f"Required unit IDs, in order: {required_unit_ids}",
            context_instruction,
            (
                "Return only the structured translation result required by "
                "the request."
            ),
            (
                "Do not include explanations, commentary, notes, Markdown, "
                "code fences, or additional prose."
            ),
            (
                "Do not include any content before or after the structured "
                "translation result."
            ),
        )
    )