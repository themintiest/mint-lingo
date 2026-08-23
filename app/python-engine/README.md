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
python -m video_translator_engine.worker
```

The worker receives and emits UTF-8 NDJSON JSON-RPC frames. Its standard output
is protocol-only; diagnostics go to standard error.
