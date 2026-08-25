# Video Translator Python engine

The local processing runtime for Video Translator. It has no runtime
dependencies and currently implements only the inert M1 JSON-RPC handshake;
it does not implement media processing, AI providers, or product behavior.

## Development

Create and activate a Python 3.13 virtual environment, then install the package
in editable mode:

```sh
python -m pip install -e .
```

Run the standard-library test suite with:

```sh
python -m unittest discover -s tests
```

To run the development worker after installation:

```sh
python -m mint_lingo_engine.worker
```

The worker receives and emits UTF-8 NDJSON JSON-RPC frames. Its standard output
is protocol-only; diagnostics go to standard error.

## Shared structured-text translation seam

LLM-01 defines source-agnostic Python domain models in
`mint_lingo_engine.translation`: `StructuredTextArtifact`, `TranslationRequest`,
and `TranslationArtifact`. A concrete workflow supplies only a canonical source
language and ordered stable unit IDs/text; a request adds a canonical target
language and optional structured reference context; results retain each unit ID with its
translated text. Projection, context construction, provider calls, validation,
retry, checkpointing, merge-back, and workflow composition are intentionally
outside this seam.

`mint_lingo_engine.llm_provider.LlmProvider` accepts a normalized
`TranslationRequest` plus provider-neutral instructions and returns a
`TranslationArtifact`, without importing a vendor adapter. Concrete providers
must normalize vendor payloads at this boundary.

CTX-01 defines `mint_lingo_engine.translation_context`
`build_translation_context_windows`. It partitions ordered source-neutral units
into bounded, non-overlapping `TranslationRequest` values while preserving each
stable unit ID and language. The caller supplies the unit bound; it is not a
provider capability or token estimate. Controlled overlap, prompts, validation,
retries, provider calls, and workflow composition remain later work.

LLM-03 defines `LlmProviderCapabilities` on `LlmProvider`. A capability
snapshot expresses available model IDs, an optional reported token context
limit, and structured-output and streaming support. It performs no provider
discovery, configuration, request-limit selection, or concrete adapter work.

`mint_lingo_engine.translation_service.TranslationService` composes bounded
context windows, provider-neutral instructions, `LlmProvider` calls, result
validation, and one immediate granular validation retry into one ordered
`TranslationArtifact`. Workflows remain responsible for job lifecycle, stage
order, checkpointing, and merge-back into their own artifacts.

## EPUB source acquisition

`mint_lingo_engine.epub_source` accepts the concrete EPUB acquisition payload
containing only a selected local `sourcePath`. It deliberately does not open or
validate the referenced file, and never accepts document bytes or reader-ready
state; EPUB package validation and artifacts are later format-owned work.

## EPUB document boundary

`mint_lingo_engine.epub_document` defines normalized package-validation errors
and the EPUB-owned `EpubDocumentArtifact` shape. Package metadata, manifest and
spine references, navigation, retained resources, serialized XHTML, and merge
targets remain there rather than in shared jobs or translation models.
