# Video Translator Python engine

The local processing runtime for Video Translator. This bootstrap package has
no runtime dependencies and does not yet implement media processing, AI
providers, or Flutter communication.

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
