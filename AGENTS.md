# AGENTS.md

## Project Overview

This repository contains a cross-platform desktop application for AI-assisted video translation.

The application consists of:

- Flutter/Dart desktop application for UI and application orchestration.
- Python processing engine for media processing, speech-to-text, and LLM-based translation.
- Shared contracts for communication between the Flutter application and Python engine.

Primary desktop targets:

- Windows
- Linux
- macOS

Refer to [technical-plan.md](docs/architecture/technical-plan.md) for detailed architecture and design decisions.

---

## General Principles

- Prefer simple, maintainable solutions over unnecessary abstraction.
- Do not introduce Clean Architecture patterns unless they provide clear value.
- Do not create an interface for every class.
- Introduce abstractions only at meaningful boundaries or substitution points.
- Keep responsibilities small and explicit.
- Avoid generic `utils`, `helpers`, or `services` dumping grounds.
- Reuse existing patterns before introducing new ones.
- Do not add dependencies without a clear reason.
- Preserve cross-platform compatibility unless a feature is explicitly platform-specific.

---

## Repository Structure

The repository is organized roughly as:

```text
app/
├── flutter/
└── python-engine/

shared/
└── schemas/

docs/

scripts/
```

Keep Flutter and Python concerns separated.

Shared protocol definitions belong under `shared/`.

---

## Flutter

Use a feature-based structure.

Typical layout:

```text
lib/
├── app/
├── common/
└── features/
```

Guidelines:

- Keep business logic outside widgets.
- Prefer BLoC/Cubit for non-trivial application state.
- Keep state granular to avoid unnecessary widget rebuilds.
- Place code inside a feature when it is only used by that feature.
- Put code in `common/` only when it is genuinely reusable.
- Keep UI responsive during all long-running operations.
- Never perform heavy AI or media processing on the Flutter UI isolate.
- Prefer immutable state and explicit state transitions.

---

## Python Engine

The Python engine owns:

- media processing
- speech transcription
- subtitle segmentation
- translation
- validation
- processing checkpoints
- AI model lifecycle and resource management

Guidelines:

- Keep domain/application logic independent from specific AI providers.
- Avoid global mutable state where practical.
- Load expensive models lazily.
- Release expensive resources when they are no longer needed.
- Long-running operations must support progress reporting and cancellation where practical.

---

## Provider Boundaries

Provider-specific implementations must remain behind meaningful abstractions.

Important boundaries include:

- `TranscriptionProvider`
- `LlmProvider`

Application logic must not depend directly on Ollama, OpenAI, faster-whisper, or another specific provider.

Provider configuration must remain replaceable.

---

## Flutter ↔ Python Communication

Flutter and Python communicate through:

**JSON-RPC over stdin/stdout.**

Rules:

- Keep the protocol structured and versionable.
- Use stable identifiers for jobs and processing entities.
- Support progress, completion, failure, and cancellation events.
- Return structured errors.
- Do not send large media content through JSON.
- Pass filesystem paths or references for large files.

Internal IPC must remain independent from communication with external AI providers.

---

## Processing

The default processing strategy should favor predictable resource usage.

Heavy AI stages should normally execute sequentially:

```text
Transcription
→ release transcription resources
→ Translation
```

Support resource policies such as:

- Balanced
- Performance
- Low Memory

Do not assume NVIDIA hardware is always available.

---

## UI / UX

Long-running operations must provide visible feedback.

Prefer:

- real progress when measurable
- indeterminate progress when not measurable
- clear current processing stage
- disabled/loading states for actions
- short and subtle transitions

Do not fake progress percentages.

Processing must never freeze the application UI.

---

## Persistence

Projects should persist enough intermediate state to resume work where practical.

Do not require completed transcription or translation stages to run again unnecessarily.

Large temporary media files should not be embedded into project metadata.

---

## Testing

When changing behavior:

- add or update relevant tests
- prefer testing domain/application behavior independently from UI
- test provider boundaries using substitutes where appropriate
- avoid tests that depend on external AI services unless explicitly intended as integration tests

Do not make real paid API calls from normal automated tests.

---

## Changes

Before implementing a significant architectural change:

1. Check the existing architecture and technical plan.
2. Prefer extending existing patterns.
3. Avoid introducing a second competing pattern for the same responsibility.
4. Update documentation when a design decision materially changes.

Do not silently change established architecture or protocol contracts.
