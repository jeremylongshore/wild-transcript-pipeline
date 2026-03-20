# 004 — Architecture Decisions: wild-transcript-pipeline

## ADR-001: Single responsibility per class

Each class has one job. Adapters parse, normalizers transform, privacy classes redact, exporters serialize. No class does more than one of these. This keeps each class testable in isolation.

## ADR-002: Immutable models

All model objects freeze their arrays and hashes at construction time. This prevents accidental mutation during pipeline processing and makes models safe to share across components. Transcripts returned from adapters are stable value objects.

## ADR-003: No runtime dependencies

The gem uses only Ruby stdlib (JSON, Time). No activesupport, no external parsing libraries. This keeps the dependency footprint minimal and makes the gem safe to embed in any Ruby environment.

## ADR-004: Configuration via block with freeze!

The configure/freeze! pattern (from wild-test-flake-forensics) provides a clear lifecycle: configure once, freeze, then the configuration is immutable. This prevents accidental config mutation during processing. reset_configuration! is provided for test isolation only.

## ADR-005: Adapters return arrays of Transcript

Even though most inputs produce a single Transcript, adapters always return an Array. This keeps the interface uniform and makes it easy to add multi-transcript adapters in the future.

## ADR-006: Intent detection is pattern-based in v1

ML-based intent classification is out of scope. Pattern matching against known phrases is deterministic, testable, and fast. The confidence scores are heuristic values calibrated to separate high-signal patterns (missing tool detection: 0.85) from weak signals (declarative "I will" sentences: 0.60).

## ADR-007: One intent per turn maximum

IntentDetector returns at most one intent per turn — the highest-confidence match. Multiple intents per turn would be noisy and difficult for gap-miner to process. If no pattern exceeds the threshold, the turn produces no intent.

## ADR-008: ToolExtractor deduplicates by (name, action, turn_index)

The same tool can appear multiple times in a single turn (e.g., mentioned twice). Deduplication by the (name, action, turn_index) triple avoids inflating tool reference counts while still capturing multiple distinct tools in the same turn.

## ADR-009: Redaction replaces, does not elide

Matched content is replaced with the redaction marker rather than deleted entirely. This preserves sentence structure and makes it clear to human reviewers that content was removed, as opposed to a missing word being a parsing artifact.

## ADR-010: Export classes do not hold state

JsonExporter and MarkdownExporter are stateless value-object processors. They accept data as method arguments and return strings. There is no internal state between export calls. This makes them thread-safe and trivial to instantiate.
