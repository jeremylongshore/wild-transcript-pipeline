# 002 — 10-Epic Build Plan: wild-transcript-pipeline

## Epic 1: Foundation and Configuration

Establish gem structure, version, error hierarchy, and validated configuration class with freeze! support. All config parameters validated with meaningful errors. Reset support for test isolation.

## Epic 2: Core Models

Build the five model classes: Turn, Intent, ToolReference, Transcript, TranscriptBatch. All immutable (frozen arrays/hashes), validated on construction, with to_h serialization. Transcript holds turns + enrichment arrays.

## Epic 3: Ingestion Adapters — Base and Claude Code

Define BaseAdapter interface. Implement ClaudeCodeAdapter to parse JSONL with role mapping (human/assistant/tool_use/tool_result/system). Handles malformed lines gracefully (skip, not raise).

## Epic 4: Ingestion Adapters — MCP Log

Implement McpLogAdapter for JSON array of JSON-RPC 2.0 request/response pairs. Matches requests and responses by id. Produces user turns for requests, tool turns for results/errors.

## Epic 5: Ingestion Adapters — Generic

Implement GenericAdapter for `{turns: [...]}`, `{messages: [...]}`, and bare array formats. Role alias mapping (human/ai/bot/function). Skips unknown roles and non-Hash entries gracefully.

## Epic 6: Normalization

Build TurnNormalizer (content truncation, turn count cap), IntentDetector (pattern-based, threshold-filtered, one intent per turn), and ToolExtractor (tool_use blocks, tool_result tags, mcp:// URIs, mcp:request/result/error markers).

## Epic 7: Privacy — Content Filter and Redactor

Build ContentFilter (pattern matching, sensitive? predicate) with built-in patterns for email, IP, API keys, AWS keys, GitHub tokens, Bearer tokens, absolute paths, file code blocks. Build Redactor (apply all patterns with gsub replacement, configurable marker, custom patterns).

## Epic 8: Export — JSON and Markdown

Implement JsonExporter returning JSON with metadata, summary, and transcripts array. Implement MarkdownExporter with human-readable sections (intents, tool refs, turns with role labels and timestamps). Both raise ExportError for invalid input.

## Epic 9: Integration and Convenience API

Implement WildTranscriptPipeline.process convenience method for full ingest-normalize-redact pipeline. Integration tests for all three adapters end to end. Cross-adapter consistency test.

## Epic 10: Adversarial Testing and Documentation

Adversarial specs for all adapters (nil, empty, truncated, wrong structure). Privacy edge cases (unicode, long content, null bytes). Export edge cases. Full 000-docs pack: blueprint, epic plan, privacy model, architecture decisions, data contracts, config reference, operator guide.
