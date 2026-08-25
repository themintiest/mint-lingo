# IPC protocol v1

This directory is the authoritative, runtime-neutral contract for version 1 of
the Flutter-to-Python IPC boundary. It defines framing, JSON-RPC envelopes,
engine-handshake messages, media inspection, and workload-agnostic job method
shapes. It does not define AI providers or concrete product-workflow payloads.

## Version

Every protocol message uses both of these fields:

```json
{
  "jsonrpc": "2.0",
  "protocolVersion": "1.0"
}
```

`jsonrpc` identifies the JSON-RPC specification. `protocolVersion` identifies
this application contract and is required on requests, notifications, and both
response types. Version 1.0 peers require an exact `protocolVersion` match;
there is no version negotiation. A changed protocol version must be published
in a new versioned contract directory with its own schemas and fixtures.

## Framing

IPC uses UTF-8 newline-delimited JSON (NDJSON) over the worker process's
standard input and output.

- A frame is one complete JSON object encoded as UTF-8 and terminated by a
  single line-feed byte (`LF`, `0x0A`). Writers must use `LF` on every platform
  and must not write a byte-order mark.
- Readers must accept both `LF` and `CRLF` input. The optional `CR` belongs to
  the delimiter and is not part of the JSON text.
- A frame contains exactly one JSON-RPC envelope object. JSON-RPC batch arrays
  are not supported.
- A sender must not emit blank frames. A receiver ignores blank `LF` or `CRLF`
  records without dispatching, responding, or treating them as diagnostics.
- Readers buffer incomplete input. A partial frame is not decoded or dispatched
  until its terminating newline arrives. Multiple complete frames received in a
  single stream read are processed in wire order.
- The JSON text of a frame, excluding its line delimiter, must not exceed
  1,048,576 UTF-8 bytes. A reader that exceeds this limit discards bytes through
  the next delimiter before resuming frame processing.

Malformed input is never dispatched. A JSON-RPC server that receives malformed
request input emits the standard JSON-RPC parse error (`-32700`, with `id` set
to `null`) for invalid UTF-8, invalid JSON, or an oversized frame. It emits the
standard invalid-request error (`-32600`) for a decoded value that does not
match this envelope contract or protocol version, echoing a valid string or
integer request ID when one can be safely recovered and otherwise using
`null`. A client that receives malformed worker output treats it as a fatal
protocol violation and stops using that worker connection. Engine errors use
the structured error-data contract below.

`stdout` is exclusively for these framed protocol messages. All logging,
diagnostics, tracebacks, and other human-readable output must go to `stderr`.

## Envelope contract

[`json-rpc-envelope.schema.json`](json-rpc-envelope.schema.json) is JSON Schema
Draft 2020-12. It accepts exactly one of:

- a request with a non-empty string or integer `id`;
- a notification with no `id` member;
- a successful response with exactly one `result` member; or
- an error response with exactly one `error` member.

`params` is optional and, when present, is an object or array as required by
JSON-RPC 2.0. `result` and `error.data` are unconstrained by the generic schema
and are constrained only where a method-specific contract requires it.

The generic envelope cannot determine whether arbitrary structured parameters
hide media content. All future method contracts must pass media only as a
filesystem path or other reference. They must not carry media bytes, base64
media, data URLs, or other embedded media payloads.

## Engine handshake messages

[`engine-lifecycle.schema.json`](engine-lifecycle.schema.json) defines the
only engine methods in M1:

- `engine.getInfo` is a request with no `params`. Its result has the engine
  semantic version and the exact IPC protocol version it implements.
- `engine.shutdown` is a request with no `params`. Its result is
  `{ "accepted": true }`; the worker flushes that response and exits.

These methods are limited to readiness and orderly shutdown. They do not load
models, inspect media, start jobs, or disclose configuration.

## Media inspection messages

[`media-inspection.schema.json`](media-inspection.schema.json) defines
`media.inspect`. It accepts exactly one parameter, `sourcePath`; media bytes,
base64 payloads, and data URLs are not permitted. A successful result contains
normalized duration, streams, dimensions, codecs, and audio presence.

Expected validation failures use JSON-RPC code `-32010` with a stable
`error.data.mediaCode`; unavailable FFprobe tooling uses `-32011` with
`error.data.toolCode`. Neither error payload may contain the supplied source
path. The media fixtures live under `fixtures/media`.

## Job-management messages

[`job-management.schema.json`](job-management.schema.json) defines the M4
contract shapes for `job.start`, `job.cancel`, and `job.get`, plus
`job.stateChanged` and `job.progress` notifications. It also defines stable
active-job-conflict and job-not-found error shapes.

`job.start` accepts an explicit opaque `workflowId` and an object-valued
`workflowPayload`. The job contract deliberately gives no source, format,
stage, artifact, language, provider, or checkpoint fields a shared meaning;
each selected concrete workflow owns its payload. This is not a workflow
registry or a promise that the inert engine worker can execute a workflow yet.

Job state contains only the stable UUIDv4 job ID and shared lifecycle. A
cancel result means a request was accepted, not that work has stopped; the
runner's cooperative cancellation boundary delivers that request to its active
workflow and its registered direct child processes. State-change notifications
represent running, completed, failed, or cancelled lifecycle values. Progress
notifications carry opaque workflow stage IDs and either exact completed/total
units or explicit indeterminate progress. They do not prescribe stage ordering
or invent percentages. Worker dispatch remains separate from the runner.

Job fixtures live under `fixtures/jobs`. They define a versioned contract only;
worker dispatch and concrete workflow composition remain separate work.

## Engine errors

[`engine-error-data.schema.json`](engine-error-data.schema.json) defines the
required `error.data` shape for engine-generated errors. Its stable
`engineCode` values map to standard JSON-RPC numeric codes:

| Engine code | JSON-RPC code | Meaning |
| --- | --- | --- |
| `engine.parse_error` | `-32700` | A frame could not be decoded as JSON. |
| `engine.invalid_request` | `-32600` | A decoded message does not match this protocol. |
| `engine.method_not_found` | `-32601` | The worker does not implement the method. |
| `engine.invalid_params` | `-32602` | The method parameters do not match their contract. |
| `engine.internal_error` | `-32603` | An unexpected worker failure occurred. |

`safeDetails` contains only a fixed reason and retryability flag. Errors must
never contain filesystem paths, parameter values, media or transcript content,
credentials, tokens, provider responses, environment values, or stack traces.
Human-readable diagnostics still go to `stderr`.

## Fixtures

The JSON files under `fixtures/valid` must validate against the schema. The
files under `fixtures/invalid` are deliberately rejected by it. Handshake
fixtures under `fixtures/engine/valid` must also match their method/error
schemas; `fixtures/engine/invalid` are deliberately rejected by those more
specific schemas. Runtime fixture conformance tests in Dart and Python are
included in IPC-TEST-01.
