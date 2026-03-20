# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Identity

- **Repo:** wild-transcript-pipeline
- **Ecosystem:** wild (see `../CLAUDE.md` for ecosystem-level rules)
- **Archetype:** B — Data Pipeline
- **Mission:** Ingest conversation transcripts from AI agent sessions, normalize into structured format, strip sensitive content, export clean data for gap-miner
- **Namespace:** WildTranscriptPipeline
- **Language:** Ruby 3.2+, pure library gem (no MCP, no ActiveRecord)
- **Status:** v1 complete — all components implemented, 200+ tests passing, 0 RuboCop offenses

## What This Repo Does

- Ingests conversation records from three source types: Claude Code session JSONL, MCP protocol logs, generic conversation JSON
- Normalizes into a common schema: Turn, Intent, ToolReference, Transcript, TranscriptBatch
- Strips sensitive content using built-in patterns (email, IP, API keys, AWS keys, GitHub tokens, absolute paths, file contents)
- Exports normalized transcripts as JSON or Markdown

## What This Repo Does NOT Do

- Collect telemetry (that's wild-session-telemetry)
- Analyze gaps (that's wild-gap-miner)
- Execute tools or manage agents
- Store raw transcripts long-term
- Communicate over a network (no HTTP, no sockets)
- Persist state to disk or a database

## Directory Layout

```
wild-transcript-pipeline/
  000-docs/               canonical documentation
  lib/
    wild_transcript_pipeline.rb          entry point, configure interface
    wild_transcript_pipeline/
      configuration.rb                   validated, freeze-on-configure config
      errors.rb                          error hierarchy
      version.rb                         VERSION = '0.1.0'
      models/                            Turn, Intent, ToolReference, Transcript, TranscriptBatch
      ingestion/                         BaseAdapter, ClaudeCodeAdapter, McpLogAdapter, GenericAdapter
      normalization/                     TurnNormalizer, IntentDetector, ToolExtractor
      privacy/                           ContentFilter, Redactor
      export/                            JsonExporter, MarkdownExporter
  spec/
    spec_helper.rb
    support/fixtures.rb                  TranscriptFixtures module
    wild_transcript_pipeline/            unit specs (mirrors lib/ structure)
    integration/                         full_pipeline_spec, cross_adapter_spec
    adversarial/                         malformed_input_spec, edge_cases_spec
  planning/               pre-implementation notes
  CHANGELOG.md
  Gemfile
  Rakefile
  wild-transcript-pipeline.gemspec
```

## Build Commands

```bash
bundle install
bundle exec rspec          # run all specs
bundle exec rubocop        # lint (must be 0 offenses)
bundle exec rake           # default: runs rspec
```

## Safety Rules for Claude Code

1. Never add code that executes shell commands, spawns subprocesses, or invokes external processes.
2. Never add code that reads from or writes to the filesystem beyond gem internals.
3. Validate all adapter input before processing; raise IngestionError on structurally invalid input.
4. Do not add network I/O, HTTP clients, or socket operations.
5. Do not add runtime gem dependencies; this gem has zero runtime dependencies by design.
6. Do not mutate configuration after freeze; use reset_configuration! in tests only.
7. Content filtering and redaction must never silence exceptions — raise PrivacyError on failure.

## Key Canonical Docs

| Doc | Purpose |
|-----|---------|
| 000-docs/001-PP-PLAN-repo-blueprint.md | Mission, boundaries, users, use cases |
| 000-docs/002-PP-PLAN-epic-build-plan.md | 10-epic build narrative |
| 000-docs/003-TQ-STND-privacy-model.md | Privacy rules and redaction rationale |
| 000-docs/004-AT-ADEC-architecture-decisions.md | Why things are shaped the way they are |
| 000-docs/005-DR-DATA-data-contracts.md | Output schema and data contracts |
| 000-docs/006-DR-REFF-configuration-reference.md | All config parameters with types and defaults |
| 000-docs/007-OD-GUID-operator-guide.md | Usage flow, config examples |

## Before Working Here

1. Read `../CLAUDE.md` for ecosystem-level rules and work sequence standards.
2. Read `000-docs/001-PP-PLAN-repo-blueprint.md` for mission and boundaries.
3. Read `000-docs/004-AT-ADEC-architecture-decisions.md` before changing structural decisions.
4. Run `bundle exec rspec` and confirm 0 failures before making changes.
5. Run `bundle exec rubocop` and confirm 0 offenses before committing.
