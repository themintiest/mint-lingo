"""Stable process entry point for the engine's JSON-RPC worker.

The implementation is kept under ``api.ipc``; this module preserves the
existing ``python -m mint_lingo_engine.worker`` launch contract.
"""

from mint_lingo_engine.api.ipc.worker import *  # noqa: F403


if __name__ == "__main__":
    raise SystemExit(main())
