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
language and optional textual context; results retain each unit ID with its
translated text. Projection, context construction, provider calls, validation,
retry, checkpointing, merge-back, and workflow composition are intentionally
outside this seam.
