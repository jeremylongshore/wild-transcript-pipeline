# wild-transcript-pipeline

Ingest conversation transcripts from AI agent sessions, normalize into a structured schema, strip sensitive content, and export clean data for downstream consumers.

## What It Does

1. **Ingest** conversation records from Claude Code JSONL logs, MCP protocol logs, and generic agent conversation JSON
2. **Normalize** into a common schema: turns (who said what), intents (what the agent was trying to do), tool_references (tools mentioned/called)
3. **Strip** sensitive content: PII, API keys, secrets, absolute paths, file contents in code blocks
4. **Export** normalized transcripts as JSON or Markdown for downstream consumers such as wild-gap-miner

## What It Does NOT Do

- Collect telemetry (that's wild-session-telemetry)
- Analyze gaps (that's wild-gap-miner)
- Execute tools or manage agents
- Store raw transcripts long-term

## Installation

```ruby
gem 'wild-transcript-pipeline'
```

## Quick Start

```ruby
require 'wild_transcript_pipeline'

adapter = WildTranscriptPipeline::Ingestion::ClaudeCodeAdapter.new
transcripts = WildTranscriptPipeline.process(jsonl_string, adapter: adapter, source_id: 'session-001')

exporter = WildTranscriptPipeline::Export::JsonExporter.new
puts exporter.export(transcripts)
```

## Configuration

```ruby
WildTranscriptPipeline.configure do |c|
  c.redaction_marker = '[REDACTED]'
  c.max_turn_content_length = 10_000
  c.max_turns_per_transcript = 1_000
  c.strip_file_contents = true
  c.strip_absolute_paths = true
  c.custom_patterns = [/MY_SECRET_PATTERN/]
  c.intent_confidence_threshold = 0.5
end
```

## Adapters

| Adapter | Input Format |
|---------|-------------|
| `ClaudeCodeAdapter` | Claude Code session JSONL (one JSON object per line) |
| `McpLogAdapter` | MCP protocol log (JSON array of request/response pairs) |
| `GenericAdapter` | Generic conversation JSON (`{turns: [...]}` or `{messages: [...]}` or array) |

## Input Formats

**Claude Code JSONL:**
```
{"type":"human","message":"Can you check the pool?","timestamp":"2026-03-19T14:00:00Z"}
{"type":"assistant","message":"Let me use inspect_connection..."}
{"type":"tool_use","name":"inspect_connection","input":{}}
{"type":"tool_result","name":"inspect_connection","output":"Pool size: 5"}
```

**MCP log:**
```
[
  {"jsonrpc":"2.0","method":"tools/call","params":{"name":"inspect_routes","arguments":{}},"id":1},
  {"jsonrpc":"2.0","result":{"content":[{"type":"text","text":"Found 42 routes"}]},"id":1}
]
```

**Generic:**
```
{"turns":[{"role":"user","content":"Show me the routes"},{"role":"assistant","content":"Let me check..."}]}
```

## Development

```bash
bundle install
bundle exec rspec          # run all specs
bundle exec rubocop        # lint
bundle exec rake           # default: rspec
```

## Ecosystem

Part of the `wild` ecosystem. See `../CLAUDE.md` for ecosystem-level conventions.

## License

Nonstandard — Intent Solutions proprietary.
