# 007 — Operator Guide: wild-transcript-pipeline

## Installation

Add to Gemfile:

```ruby
gem 'wild-transcript-pipeline'
```

Then `bundle install`.

## Basic Workflow

### Step 1: Choose an adapter

| Source | Adapter |
|--------|---------|
| Claude Code JSONL session log | `ClaudeCodeAdapter` |
| MCP protocol log (JSON array) | `McpLogAdapter` |
| Generic conversation JSON | `GenericAdapter` |

### Step 2: Parse input

```ruby
require 'wild_transcript_pipeline'

adapter = WildTranscriptPipeline::Ingestion::ClaudeCodeAdapter.new
transcripts = adapter.parse(File.read('session.jsonl'), source_id: 'session-2026-001')
```

### Step 3: Normalize (optional if using process convenience method)

```ruby
normalizer = WildTranscriptPipeline::Normalization::TurnNormalizer.new
normalized_turns = normalizer.normalize(transcripts.first.turns)
```

### Step 4: Detect intents and tool references

```ruby
detector = WildTranscriptPipeline::Normalization::IntentDetector.new
extractor = WildTranscriptPipeline::Normalization::ToolExtractor.new

intents = detector.detect(normalized_turns)
tool_refs = extractor.extract(normalized_turns)
```

### Step 5: Redact

```ruby
redactor = WildTranscriptPipeline::Privacy::Redactor.new
redacted_transcript = redactor.redact_transcript(transcripts.first)
```

### Step 6: Export

```ruby
exporter = WildTranscriptPipeline::Export::JsonExporter.new
json_output = exporter.export([redacted_transcript])
File.write('output.json', json_output)
```

## Convenience Method

For the full ingest-normalize-redact pipeline in one call:

```ruby
transcripts = WildTranscriptPipeline.process(
  File.read('session.jsonl'),
  adapter: WildTranscriptPipeline::Ingestion::ClaudeCodeAdapter.new,
  source_id: 'session-001'
)
```

## Configuration Example

```ruby
WildTranscriptPipeline.configure do |c|
  c.redaction_marker = '[REMOVED]'
  c.max_turn_content_length = 5_000
  c.max_turns_per_transcript = 500
  c.strip_file_contents = true
  c.strip_absolute_paths = true
  c.custom_patterns = [/corp\.internal/i, /CORP_SECRET_[A-Z0-9]+/]
  c.intent_confidence_threshold = 0.6
end
```

## Reading Exported JSON

The JSON output contains:
- `metadata.generated_at` — when the export was created
- `summary.transcript_count` — total transcripts in this export
- `summary.total_tool_references` — total tool references (check for `not_found` action for gaps)
- `transcripts[].intents` — detected agent intents (what it was trying to do)
- `transcripts[].tool_references` — tools mentioned, called, or reported missing

## Identifying Gaps from Tool References

Tool references with `action: "not_found"` and `outcome: "not_available"` indicate that the agent could not find a tool to accomplish something. These are primary input for wild-gap-miner analysis.

## Markdown Export for Human Review

```ruby
exporter = WildTranscriptPipeline::Export::MarkdownExporter.new
md = exporter.export(transcripts)
File.write('review.md', md)
```

The Markdown output is structured with sections per transcript, listing intents, tool references, and full turn-by-turn conversation.
