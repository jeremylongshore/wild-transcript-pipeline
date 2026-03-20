# 001 — Repo Blueprint: wild-transcript-pipeline

## Mission

Ingest conversation transcripts from AI agent sessions, normalize into a structured schema, strip sensitive content, and export clean data for downstream consumers (primarily wild-gap-miner).

## Boundaries

**In scope:**
- Parsing Claude Code JSONL session logs
- Parsing MCP protocol request/response logs
- Parsing generic agent conversation JSON
- Normalizing all formats into Turn / Intent / ToolReference / Transcript / TranscriptBatch
- Stripping PII, secrets, absolute paths, and file contents via configurable patterns
- Exporting as JSON or Markdown

**Out of scope:**
- Collecting telemetry (wild-session-telemetry)
- Analyzing gaps (wild-gap-miner)
- Executing tools, invoking agents, or running code
- Long-term storage of raw or normalized transcripts
- Network communication
- Authentication, authorization, or access control

## Primary Users

1. **wild-gap-miner** — downstream consumer of normalized transcripts (machine-to-machine)
2. **Operators** — human engineers who want to inspect session transcripts in readable form
3. **CI pipelines** — automated transcript normalization as part of a processing pipeline

## Key Use Cases

1. Ingest a Claude Code session JSONL file and produce a normalized, redacted Transcript
2. Process a batch of MCP logs and export as JSON Lines for gap-miner
3. Load a generic conversation JSON and render as Markdown for review
4. Apply custom PII patterns on top of built-in redaction rules
5. Configure turn and content limits to cap transcript size

## Non-Goals

- Building a storage backend or database interface
- Providing a web API or HTTP server
- Implementing AI/ML-based intent classification (pattern-based only in v1)
- Producing diffs between transcript versions

## Success Criteria for v1

- All three adapters parse their respective formats correctly
- Privacy redaction removes all built-in sensitive content types
- Configuration supports all documented parameters with validation
- JSON and Markdown exporters produce valid, well-structured output
- 200+ tests passing with 0 failures and 0 RuboCop offenses
