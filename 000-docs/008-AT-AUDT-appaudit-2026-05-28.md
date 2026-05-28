# 008 — Operator-Grade Audit: wild-transcript-pipeline

**Date:** 2026-05-28
**Auditor:** Claude Code (operator-grade pass)
**Repo version:** v0.1.0 (per `lib/wild_transcript_pipeline/version.rb`)
**Audience:** senior Rails/Ruby engineer, first read, ~10 minutes to operate
**Status under review:** v1 complete — all components implemented, 200+ specs, 0 RuboCop offenses

---

## 1. Mission & Boundaries

`wild-transcript-pipeline` is a **pure Ruby library gem** (no MCP, no ActiveRecord, no network, no disk I/O beyond gem internals) whose sole job is to take an AI-agent conversation transcript in one of three accepted on-the-wire formats, turn it into a uniform in-memory object graph, scrub the content of obvious secrets/PII, and hand the result to a caller as either a JSON string or a Markdown string. It is one of ten gems in the `wild` ecosystem (see `../CLAUDE.md`), classified as Archetype B (Data Pipeline).

**What it processes** (per `lib/wild_transcript_pipeline/ingestion/`):

- **Claude Code session JSONL** — one JSON object per line, with `type` in `{human, user, assistant, tool_use, tool_result, system}` (`claude_code_adapter.rb:8-15`).
- **MCP protocol logs** — a JSON array of JSON-RPC 2.0 request/response pairs, paired by `id` (`mcp_log_adapter.rb:25-50`).
- **Generic conversation JSON** — any object shaped `{turns:[...]}`, `{messages:[...]}`, or a bare array of `{role, content}` entries (`generic_adapter.rb:43-53`).

**What it explicitly does NOT do** (per `CLAUDE.md` § "What This Repo Does NOT Do" and `README.md:12-17`):

- No telemetry collection (`wild-session-telemetry` owns that).
- No gap analysis (`wild-gap-miner` owns that).
- No tool execution or agent management.
- No long-term storage of raw transcripts. The library produces an output string and returns; the caller decides what to persist.
- No network I/O of any kind. No HTTP client, no sockets.
- No filesystem I/O. The library reads from in-memory strings and writes to returned strings.
- No runtime gem dependencies (`wild-transcript-pipeline.gemspec` has zero `add_dependency` calls; only stdlib `json` and `time` are required).

**Inputs are strings, outputs are strings.** That is the discipline. `WildTranscriptPipeline.process(input_string, adapter:, source_id:)` returns `Array<Models::Transcript>`; `JsonExporter#export(transcripts)` returns a JSON string. The library is trivially testable, trivially callable from a Rails console, and has no startup cost beyond `require`.

**Boundary with the upstream `wild-session-telemetry` gem:** the sibling repo's CLAUDE.md and `004-AT-STND-data-contracts.md §6.3` declare transcript-pipeline as a downstream consumer of session-telemetry's export schema. **As of v0.1.0, no such adapter exists in `lib/wild_transcript_pipeline/ingestion/`.** A `grep` for `session.telemetry`, `wild_session`, or `json.lines` across the entire `lib/` tree returns zero hits. This is a documented but unimplemented integration. See §4 for the full cross-repo drift discussion.

---

## 2. Pipeline Architecture

The library is a four-stage in-process pipeline. There is no batching framework, no retry queue, no worker pool, no checkpointing, no persistence between calls. **Each call to `WildTranscriptPipeline.process` runs the four stages synchronously, in order, on a single input string, and returns the result.** The caller is responsible for any concurrency, batching, or retry behavior.

The four stages live in three subdirectories of `lib/wild_transcript_pipeline/` and are wired together by the module-level `process` method (`lib/wild_transcript_pipeline.rb:47-51`).

### Stage 1 — Ingestion (`ingestion/`)

The caller picks an adapter and passes it in:

```ruby
adapter = WildTranscriptPipeline::Ingestion::ClaudeCodeAdapter.new
transcripts = WildTranscriptPipeline.process(jsonl_string, adapter: adapter, source_id: 'session-001')
```

All three adapters (`ClaudeCodeAdapter`, `McpLogAdapter`, `GenericAdapter`) inherit from `BaseAdapter` (`ingestion/base_adapter.rb`), which provides `require_non_empty!`, `coerce_source_id`, `parse_timestamp`, and `build_turn` helpers. Each adapter's `#parse(input, source_id:)` method returns `Array<Models::Transcript>` — always a one-element array in the current implementation, but the type leaves the door open for multi-transcript files.

Adapters raise `IngestionError` on structurally invalid input (e.g., MCP log that isn't a JSON array, `mcp_log_adapter.rb:27`). They silently skip individual unparseable lines in JSONL (`claude_code_adapter.rb:52-54` — the `JSON::ParserError` rescue returns `nil` and `filter_map` drops it). This is a deliberate asymmetry: a malformed file fails loudly; a malformed line in a long log file is dropped quietly to preserve the rest.

### Stage 2 — Normalization (`normalization/`)

Three classes, each instantiated fresh by `build_pipeline` (`lib/wild_transcript_pipeline.rb:55-62`):

- `TurnNormalizer#normalize(turns, config:)` — caps the array to `config.max_turns_per_transcript` (default 1,000) and each turn's content to `config.max_turn_content_length` (default 10,000 chars). Truncation is silent — no warning, no metadata flag (`turn_normalizer.rb:15-36`).
- `IntentDetector#detect(turns, config:)` — regex-scans user and assistant turns against twelve hand-curated `INTENT_PATTERNS` (`intent_detector.rb:6-19`), emits at most one `Intent` per turn (the highest-confidence match, `intent_detector.rb:43-46`), gated by `config.intent_confidence_threshold` (default 0.5). Skips turns that look like tool calls.
- `ToolExtractor#extract(turns)` — regex-scans every turn for MCP requests/results/errors, `[tool_use]`/`[tool_result:]` blocks, `mcp://` URIs, `"can't find a tool"` phrases, and as a fallback for assistant turns only, `name({...})`-shaped explicit calls (`tool_extractor.rb:6-13, 27-38`). Deduplicates within a turn by `(name, action, turn_index)`.

### Stage 3 — Privacy (`privacy/`)

`Redactor#redact_turn` and `Redactor#redact_transcript` apply seven built-in regex patterns from `ContentFilter` (email, IP, generic API key, AWS access/secret, GitHub token, bearer token), plus optionally `FILE_CONTENT_PATTERN` (fenced code blocks) and `ABSOLUTE_PATH_PATTERN`, plus any user-supplied `config.custom_patterns` (`redactor.rb:45-64`). Replacement is the literal `config.redaction_marker` (default `[REDACTED]`).

The redactor runs **twice** in the pipeline: once per turn during the main pass (`lib/wild_transcript_pipeline.rb:66`) and once over the whole enriched transcript at the end (`lib/wild_transcript_pipeline.rb:70`). The second pass appears to be belt-and-braces — it re-runs `redact_turn` over already-redacted turns, which is idempotent for the built-in patterns but adds a `metadata.redacted = true` flag.

### Stage 4 — Export (`export/`)

`JsonExporter#export(transcripts)` builds a payload `{metadata, summary, transcripts: [...]}` and serializes with `JSON.generate`. `MarkdownExporter` produces a human-readable text format for review. Neither writes to disk; both return strings.

**There is no chaining, no batching framework, no retries.** The chain is one Ruby method call (`WildTranscriptPipeline.process`) executing four stages back-to-back. If a stage raises, the caller sees the exception immediately; no partial result is returned.

---

## 3. The Critical Path

Tracing a Claude Code JSONL string from input to JSON output, using real method names from `lib/`:

1. **Caller** constructs `ClaudeCodeAdapter.new` and calls `WildTranscriptPipeline.process(jsonl, adapter:, source_id: 'session-001')` (`lib/wild_transcript_pipeline.rb:47`).
2. **`process`** calls `adapter.parse(input, source_id: 'session-001')`. `ClaudeCodeAdapter#parse` runs `require_non_empty!`, splits on `\n`, drops blank lines, then for each line calls `parse_line` → `JSON.parse` → `resolve_role` (maps `type` → `:user`/`:assistant`/`:tool`/`:system` via `TYPE_TO_ROLE`) → `extract_content` (special-cases `tool_use` and `tool_result` types) → `parse_timestamp` → `extract_metadata` → `build_turn` (`claude_code_adapter.rb:17-87`). Returns `[Models::Transcript.new(source_type: :claude_code, ...)]`.
3. **`process`** then calls `build_pipeline` (creates fresh `TurnNormalizer`, `IntentDetector`, `ToolExtractor`, `Redactor`) and `run_pipeline(transcript, pipeline, config)` for each transcript (`lib/wild_transcript_pipeline.rb:49-51`).
4. **`run_pipeline`** (`lib/wild_transcript_pipeline.rb:64-71`) executes the stages explicitly:
   - `pipeline[:normalizer].normalize(transcript.turns, config: config)` → returns capped, truncated `Array<Models::Turn>`.
   - `turns.map { |t| pipeline[:redactor].redact_turn(t, config: config) }` → returns redacted turns.
   - `pipeline[:intent_detector].detect(turns, config: config)` → returns `Array<Models::Intent>` (each carries `description`, `confidence`, `source_turn_index`).
   - `pipeline[:tool_extractor].extract(turns)` → returns `Array<Models::ToolReference>`.
   - `build_enriched_transcript(transcript, turns, intents, tool_refs)` → constructs a new `Models::Transcript` with all four collections plus `metadata.processed = true`.
   - `pipeline[:redactor].redact_transcript(enriched, config: config)` → final pass that wraps the transcript with `metadata.redacted = true` and re-redacts each turn (idempotent for built-in patterns).
5. **Caller** receives `Array<Models::Transcript>` and passes to `JsonExporter.new.export(transcripts)` (`export/json_exporter.rb:8-15`), which calls `build_payload` → `JSON.generate` and returns a JSON string with top-level `metadata`, `summary`, and `transcripts` keys.

Total in-process latency for a typical session JSONL (low hundreds of turns) is dominated by JSON parsing and the linear regex scan in `Redactor`. No async, no I/O, no DB; the call returns when the string is built.

---

## 4. Data Contracts (and the gap-miner drift)

### Input contract

Each adapter defines its input contract narrowly:

| Adapter | Accepted input | Source enum value | Rejection condition |
|---|---|---|---|
| `ClaudeCodeAdapter` | JSONL string (one JSON object per line) | `:claude_code` | Empty input → `IngestionError`. Unparseable individual lines → silently skipped. |
| `McpLogAdapter` | JSON string containing a JSON array of JSON-RPC objects | `:mcp_log` | Empty input, non-array root, or `JSON::ParserError` → `IngestionError`. |
| `GenericAdapter` | JSON object with `turns`/`messages` array, or bare JSON array | `:generic` | Empty input, non-array container, or `JSON::ParserError` → `IngestionError`. |

There is **no adapter** for the `wild-session-telemetry` JSON Lines export format. The transcript-pipeline gem does not currently accept telemetry-format input.

### Output contract

Defined in `000-docs/005-DR-DATA-data-contracts.md` and produced by `JsonExporter#export` (`export/json_exporter.rb:25-49`). Top-level shape:

```json
{
  "metadata": { "generated_at": "<iso8601>", "version": "<gem version>", "schema_version": "1.0" },
  "summary":  { "transcript_count": N, "total_turns": N, "total_intents": N,
                "total_tool_references": N, "source_types": ["<symbol>"] },
  "transcripts": [
    {
      "source_type": "<symbol: claude_code | mcp_log | generic>",
      "source_id":   "<string>",
      "created_at":  "<iso8601>",
      "turns":            [ { role, content, timestamp, metadata } ],
      "intents":          [ { description, confidence, source_turn_index } ],
      "tool_references":  [ { name, action, outcome, turn_index } ],
      "metadata":         { ... }
    }
  ]
}
```

Schema stability is asserted at the `schema_version: "1.0"` marker (`000-docs/005-DR-DATA-data-contracts.md:74-76`): additive minor changes only, no rename or removal without a version bump.

### Cross-repo drift — the gap-miner consumer claim

**The drift is bidirectional and explicit.** Both this repo and `wild-session-telemetry` describe `wild-gap-miner` as a downstream consumer that does not actually consume what they document.

**This repo says (`000-docs/005-DR-DATA-data-contracts.md §"Downstream Consumer Contract (wild-gap-miner)"`, lines 78-85):**

> Gap-miner expects:
> - `transcripts[].turns` to contain redacted content (no raw PII)
> - `transcripts[].intents` for gap detection (missing capabilities)
> - `transcripts[].tool_references` where action=:not_found signals a gap
> - `metadata.schema_version` to be checked before processing

**Sibling `wild-session-telemetry/000-docs/004-AT-STND-data-contracts.md §6.3 "Cross-Repo Contract Ownership" (line 377):**

> | Export schema | `wild-session-telemetry` | `wild-gap-miner` | Telemetry owns schema; gap-miner depends on it |

**The reality, from `wild-gap-miner/lib/`:** zero files reference "transcript" anywhere in the code. Gap-miner's `lib/wild_gap_miner/ingestion/` contains exactly two files (`export_parser.rb`, `record_factory.rb`); its models are `event_record`, `telemetry_record`, `pattern_record`, `tool_utilization` — none of which match the transcript-pipeline or session-telemetry output schemas. The gap-miner audit (`wild-gap-miner/000-docs/007-AT-AUDT-appaudit-2026-05-28.md`) independently confirms gap-miner has no transcript-handling code path.

**The drift is a documentation artifact, not a code regression** — gap-miner was apparently spec'd against an earlier ecosystem plan in which it would consume from both upstream gems; the implementation diverged and the upstream contracts were never updated. Both this repo's §"Downstream Consumer Contract" section and `wild-session-telemetry`'s §6.3 ownership table need to either (a) be deleted, (b) be reframed as "intended for future gap-miner v2 ingestion," or (c) drive new work to add a transcript-aware ingestor to gap-miner. **A senior engineer reading this contract today and assuming a live wire to gap-miner will be wrong.** Flag this on first read.

---

## 5. Failure Modes & Blast Radius

The library has a small attack surface because it has no I/O, no state, and no concurrency. The failure modes that matter are all about how it handles bad input or excessive load.

| Failure | Where it surfaces | Blast radius | Recovery |
|---|---|---|---|
| **Malformed entire input** (empty string, non-JSON when JSON expected, MCP root is object not array) | Adapter `#parse` raises `IngestionError` (`mcp_log_adapter.rb:27, 31`; `generic_adapter.rb:40, 51`) | Single call fails. No state to corrupt — library holds none. | Caller catches `IngestionError`, logs, drops or retries with different adapter. |
| **Malformed individual line in JSONL** | `ClaudeCodeAdapter#parse_line` rescues `JSON::ParserError`, returns `nil`, `filter_map` silently drops it (`claude_code_adapter.rb:52-54`) | One turn lost from that transcript. No surfaced count of dropped lines. | None automatic. To detect, diff `metadata.line_count` (raw line count) against `transcript.turn_count` after the fact. |
| **Schema drift in source format** (Claude Code emits a new `type` not in `TYPE_TO_ROLE`) | `resolve_role` returns `nil`, `parse_line` returns `nil`, line silently skipped (`claude_code_adapter.rb:43-45`) | Whole class of turns invisibly disappears from output. | Engineer-level: monitor `line_count` vs `turn_count` skew; periodically re-grep raw input for unknown `type` values and extend `TYPE_TO_ROLE`. |
| **Oversized transcript** (>1,000 turns or >10,000-char turn content) | `TurnNormalizer` silently truncates (`turn_normalizer.rb:15-19, 33-36`) | Lost turns / lost content past the cap. No surfaced warning. | Raise `config.max_turns_per_transcript` / `config.max_turn_content_length` before processing. No retry needed — re-run with bigger caps. |
| **Processor crash mid-pipeline** (e.g., bad turn breaks `IntentDetector`) | Exception bubbles up to `WildTranscriptPipeline.process` caller. | One transcript fails; pipeline is in-process and stateless, so nothing else affected. **There is no batched-loop retry mechanism — the caller's `.map` loop will halt mid-batch.** | Caller must wrap each transcript in `begin/rescue` and decide per-item whether to continue. |
| **Privacy regex false negative** (a new secret format isn't covered) | Secret is exported in plaintext in the JSON output. | Real privacy incident. Blast radius is whoever consumes the export string. | Add a `config.custom_patterns` Regexp before the breach happens (operationally: review fixtures + adversarial specs after every secret-format change in upstream tooling). |
| **Privacy regex false positive** (legitimate content matches `[REDACTED]`) | Real content is destroyed in the output; original is gone because the library doesn't keep it. | Permanent for that output; original input string is still in the caller's hand if they kept it. | Tune the offending pattern and reprocess from the original input. |
| **Downstream consumer unavailable** | N/A — there is no live wire. The library produces a string and returns. Whoever consumes it is the caller's problem. | None at this layer. | Operate at the caller; this library is unaffected by downstream availability. |

**No automatic batched retry, no DLQ, no checkpointing exists.** The caller is the orchestration layer. This is by design (per `004-AT-ADEC-architecture-decisions.md` and `CLAUDE.md` safety rule "no filesystem", "no network") and is the right shape for a pure library — but a senior engineer should not expect this gem to do any of those things on its own.

---

## 6. Trade-off Analysis

| Decision | What was chosen | Alternative considered | Why this is the right call (for now) | Cost |
|---|---|---|---|---|
| **Zero runtime dependencies** | `wild-transcript-pipeline.gemspec` declares no `add_dependency`; library uses only `json` and `time` from stdlib (`lib/wild_transcript_pipeline.rb:3`). | Pull in `dry-validation`, `oj`, `multi_json`, an intent-detection ML model, or a privacy library such as `pii_scrubber`. | The gem is consumed in environments where any added dep is a supply-chain risk. Zero deps means trivial install, no version conflicts, no transitive CVE exposure. The library is small enough that hand-rolling validation in `Configuration` and intent matching in `IntentDetector` costs ~250 LoC total. | Validation is bespoke (every setter has its own `check_frozen!` + type check, `configuration.rb:23-86`). Intent detection is twelve hand-curated regexes (`intent_detector.rb:6-19`) with no learning, no language portability, no statistical confidence — just `base_confidence + 0.05 if content > 200 chars` (`intent_detector.rb:77-81`). |
| **Pure in-process, no I/O** | All inputs are Ruby strings; all outputs are Ruby strings. No disk, no network, no DB, no queue. The four safety rules in `CLAUDE.md` lock this in. | A daemonized pipeline (Sidekiq worker, Kafka consumer, file-watching daemon) that auto-batches and persists. | Easy to test (every spec is one method call with a fixture string), easy to reason about (no concurrency), easy to embed (Rails console, a one-off Rake task, a CI sweep can all use it identically). | The caller takes on all batching, retry, checkpointing, and concurrency concerns. There is no built-in "ingest a directory of JSONL files" entry point — every caller writes the same loop. |
| **Adapter-per-source-format vs. universal schema** | Three concrete adapters (`ClaudeCodeAdapter`, `McpLogAdapter`, `GenericAdapter`) all inheriting from `BaseAdapter` and emitting the same `Models::Transcript`. | A single "universal" adapter parameterized by a config map; or pushing source-format detection into a sniffer. | New source formats add one file under `ingestion/`. The `BaseAdapter` extracts the genuinely shared helpers (`coerce_source_id`, `parse_timestamp`, `build_turn`) without overreaching. Each adapter's logic is local and grep-able. | Three adapters means three sets of role-mapping tables (`TYPE_TO_ROLE` in `claude_code_adapter.rb:8-15`, `ROLE_MAP` in `generic_adapter.rb:8-17`, implicit in `mcp_log_adapter.rb`). When a new role concept enters the ecosystem, three places have to change. Modest duplication is the price of localness. |
| **Silent drop of malformed JSONL lines** | `ClaudeCodeAdapter#parse_line` rescues `JSON::ParserError` and returns `nil`, which `filter_map` drops (`claude_code_adapter.rb:40-54`). No counter, no log, no metadata field. | Raise on first bad line; or emit a `metadata.dropped_lines` counter; or accumulate dropped-line errors and surface in `Transcript.metadata`. | Real Claude Code session logs occasionally contain truncated last lines (process killed mid-write) or non-JSON debug emissions. Failing the whole transcript on one bad line would be hostile. | **Silent data loss is invisible.** A schema drift that introduces a new top-level `type` will silently drop every turn of that type, and the operator has no signal until output volume drops. The `metadata.line_count` field exists (`claude_code_adapter.rb:30`) but reconciling it against `turn_count` is an out-of-band check the operator must remember to perform. Recommend tracking a `dropped_lines` counter in v0.2. |
| **Hand-rolled regex intent detection** | Twelve regex patterns + naive length-based confidence (`intent_detector.rb:6-19, 77-81`). | Ship a small classifier (logistic regression on bag-of-words), or pull in a transformer, or call out to an LLM. | Zero deps, zero runtime cost, deterministic, auditable, every false positive/negative is fixable by editing a regex. Intent detection is a hint for downstream consumers, not a load-bearing decision. | Recall is low for any phrasing not on the twelve-pattern list; precision suffers when assistants narrate in styles like "I'll check that for you" (matched) vs. "checking that now" (unmatched). The whole subsystem is best viewed as a heuristic preview, not a primary signal. |
| **Two-pass redaction in `run_pipeline`** | `redact_turn` runs once on each turn after normalization (line 66), then `redact_transcript` runs at the end (line 70) and re-redacts each turn. | Single redaction pass at the end. | The first pass redacts before `IntentDetector` and `ToolExtractor` see content — so derived intents and tool refs are built from already-redacted text and never leak secrets. The second pass is defensive idempotency + flags `metadata.redacted = true`. | Double CPU cost for redaction (linear regex scan, runs twice). For 1,000-turn / 10,000-char transcripts this is meaningful. Could be optimized to one pass with metadata-flag-only second wrap. |

---

## 7. Operator Playbook

**Run the pipeline (Rails console, IRB, or Rake task):**

```ruby
require 'wild_transcript_pipeline'

jsonl = File.read('/tmp/session-001.jsonl')                # caller's I/O
adapter = WildTranscriptPipeline::Ingestion::ClaudeCodeAdapter.new
transcripts = WildTranscriptPipeline.process(jsonl, adapter: adapter, source_id: 'session-001')

json = WildTranscriptPipeline::Export::JsonExporter.new.export(transcripts)
File.write('/tmp/session-001.processed.json', json)         # caller's I/O
```

**Inspect a batch of transcripts in-memory before exporting:**

```ruby
batch = WildTranscriptPipeline::Models::TranscriptBatch.new(transcripts: transcripts)
puts batch.size                # transcript count
puts batch.total_turns         # turns across all
puts batch.total_intents       # intents across all
puts batch.total_tool_references
puts batch.source_types        # e.g. [:claude_code]
```

`TranscriptBatch#to_h` (`models/transcript_batch.rb:41-53`) is the canonical inspection view. `JsonExporter#export_batch(batch)` is the canonical batch export path.

**Detect silent line drops (the §5 schema-drift failure mode):**

```ruby
t = transcripts.first
raw_line_count = t.metadata[:line_count]  # set by ClaudeCodeAdapter
turn_count     = t.turn_count
skew           = raw_line_count - turn_count
warn "dropped #{skew} lines from #{t.source_id}" if skew > 0
```

If skew is non-zero, eyeball the original JSONL with `jq` and look for `type` values not in `TYPE_TO_ROLE` (`lib/wild_transcript_pipeline/ingestion/claude_code_adapter.rb:8-15`).

**Requeue a failed item (the library has no built-in queue):**

The library is stateless and the caller owns the queue. The recovery pattern is: keep the original input string, re-run `WildTranscriptPipeline.process` with the same or adjusted config. There is no DLQ, no checkpoint, no retry-with-backoff helper.

**Recover from schema drift:**

When upstream Claude Code or an MCP server emits a new `type` / role / event shape:

1. Identify the new value by grepping the source format.
2. Add it to `TYPE_TO_ROLE` (`claude_code_adapter.rb:8-15`) or `ROLE_MAP` (`generic_adapter.rb:8-17`).
3. Add a spec in `spec/wild_transcript_pipeline/ingestion/` covering it.
4. Bump the gem version per semver — additive parsing is a minor bump; behavior change (e.g., re-routing an existing role) is a major bump under the schema 1.0 stability guarantee.
5. Re-run `WildTranscriptPipeline.process` over any saved raw inputs the operator wants to back-fill.

**Tune redaction:**

If a known-secret format leaks (e.g., a new vendor's API key format), add it to `config.custom_patterns` before any further runs and re-process. Existing exports are not retroactively scrubbed — the original input string is the only re-source.

```ruby
WildTranscriptPipeline.reset_configuration!  # tests only; un-freezes
WildTranscriptPipeline.configure do |c|
  c.custom_patterns = [/sk-vendor-[A-Za-z0-9]{32}/]
end
```

---

## 8. Recommendations for v2

**Honest assessment.** v0.1.0 is a tight, defensible, well-tested pure library. The architecture decisions (zero deps, no I/O, in-process pipeline, adapter-per-format) are the right shape for the stated mission. Most of what's missing is genuinely out of scope for the library and belongs in the caller. The non-trivial issues:

1. **Fix the cross-repo doc drift around `wild-gap-miner`.** `000-docs/005-DR-DATA-data-contracts.md §"Downstream Consumer Contract"` (lines 78-85) asserts a consumer that does not exist in gap-miner's actual code. Either delete the section, retitle it "Intended consumer (not yet implemented in gap-miner v0.x)", or drive new work to add a transcript-ingestor to gap-miner. The mirrored claim in `wild-session-telemetry/000-docs/004-AT-STND-data-contracts.md §6.3` (line 377) needs the same treatment. Today, a senior reader trusting either doc is being misled.

2. **Decide and document the session-telemetry → transcript-pipeline integration.** `wild-session-telemetry/CLAUDE.md` says transcript-pipeline is a downstream consumer. No `SessionTelemetryAdapter` exists in `lib/wild_transcript_pipeline/ingestion/`. Either build it (add the adapter, document the JSON Lines record → Turn mapping) or remove the claim from session-telemetry's CLAUDE.md.

3. **Surface silent data loss.** Add a `metadata.dropped_lines` counter to every adapter and warn-on-skew when reconciling against `turn_count`. The current silent-drop behavior is correct, but operators have no signal when schema drift starts eating turns.

4. **Single-pass redaction with metadata-only second wrap.** The current two-pass redaction (`lib/wild_transcript_pipeline.rb:66, 70`) is defensive idempotency at double the regex CPU cost. Refactor to one pass + a cheap `metadata.merge(redacted: true)` second wrap.

5. **Consider a `process_each` streaming entry point** for callers handling large directories of JSONL — current API forces the caller to hold each input as a full string in memory and `.map` the result. A `Enumerator`-returning sibling would be cheap to add and would not violate the "no I/O" rule (the caller still opens the file).

Out of scope for v2, by design: batching framework, retry queue, persistence, network ingestion. Those belong in the caller or in a separate orchestrator gem.

---

## Findings summary

The repo is solid: pure library, zero deps, four-stage in-process pipeline, three adapters, sane privacy defaults, clear safety rules. Critical-path is one method call (`WildTranscriptPipeline.process`) executing ingest → normalize → redact → detect-intents → extract-tools → re-redact → return; outputs serialize to a versioned JSON envelope. **Cross-repo issues confirmed:** (1) `000-docs/005-DR-DATA-data-contracts.md §"Downstream Consumer Contract (wild-gap-miner)"` asserts a consumer that doesn't exist — gap-miner's `lib/` has zero references to "transcript", confirmed independently by gap-miner's own audit; (2) `wild-session-telemetry/000-docs/004-AT-STND-data-contracts.md §6.3 line 377` mirrors the same false claim from the upstream side; (3) session-telemetry also declares transcript-pipeline as a downstream consumer of telemetry exports, but no `SessionTelemetryAdapter` exists in this repo. All three claims need either deletion, reframing as "intended/future", or new implementation work. Secondary issues: silent line-drop in `ClaudeCodeAdapter#parse_line` has no operator-visible counter; two-pass redaction doubles regex CPU for no behavioral gain.
