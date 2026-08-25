# REVIEW.md

Repository-specific law for the automated pull-request reviewer (MiniMax, two advisory lanes).

This gem takes untrusted AI agent conversation logs, normalizes them, strips secrets and PII, and
hands the result to downstream consumers such as wild-gap-miner. Every defect that matters here is
either "sensitive content escaped" or "the library grew a capability it is not allowed to have".
Review only what the pull request changes, most severe first, and verify each finding against the
surrounding source. The deterministic gate is CI (`bundle exec rspec` on Ruby 3.2 and 3.3, plus
`bundle exec rubocop` at zero offenses). The reviewer's job is the part CI cannot phrase.

## Authority

Read `CLAUDE.md` first (its "Safety Rules for Claude Code" are binding), then
`000-docs/003-TQ-STND-privacy-model.md` for the privacy contract,
`000-docs/005-DR-DATA-data-contracts.md` for the export schema, and
`000-docs/004-AT-ADEC-architecture-decisions.md` before accepting any structural change. A PR
description is not authority. A doc that contradicts the code is a finding, not a license.

## Top defect classes, in order of risk

1. **Redaction bypass.** `Privacy::Redactor` is the only thing standing between a raw session log
   and an exported artifact. Flag any new path that reaches `Export::JsonExporter` or
   `Export::MarkdownExporter` without passing `redact_turn` / `redact_transcript`, any new public
   entry point that parallels `WildTranscriptPipeline.process` but skips the redactor, and any stage
   inserted **after** redaction in `run_pipeline` that reassembles, re-reads, or re-injects original
   content. Redaction must be the last thing that touches turn content.
2. **Ordering that defeats a pattern.** `TurnNormalizer` truncates to
   `max_turn_content_length` before the redactor runs. Truncation that splits a token can leave a
   fragment no pattern matches. Any change to stage order, to truncation, or to content joining
   must be justified against this, and needs a spec proving a secret straddling the boundary still
   gets redacted.
3. **Pattern regressions in `Privacy::ContentFilter`.** Removing a constant from
   `BUILT_IN_PATTERNS`, loosening an anchor, narrowing a character class, or dropping a pattern from
   the `apply_built_in_patterns` chain in `Redactor` is a privacy regression even when every spec
   still passes: `BUILT_IN_PATTERNS` (seven constants) and the redactor's chain (those seven plus
   two config-gated ones) are two separate lists and they drift. Flag when a pattern is added to one
   and not the other. Also flag catastrophic-backtracking regexes on attacker-controlled content.
   `ABSOLUTE_PATH_PATTERN` is the existing nested-quantifier one; `FILE_CONTENT_PATTERN` is not
   nested, it is an unbounded lazy scan across the whole content. Input here is untrusted log text,
   so a pathological regex is a denial of service, not a nit.
4. **Widening the metadata carve-out.** `Turn#metadata` is deliberately **not** redacted
   (`003-TQ-STND-privacy-model.md`, "Scope Limitation"), yet `Turn#to_h` emits it and the JSON
   exporter ships it. `ClaudeCodeAdapter` already puts raw `tool_input` and `tool_output` there. The
   carve-out itself is a recorded decision, so do not relitigate it. DO flag anything that makes it
   worse: a new adapter stuffing raw payload into `metadata`, an exporter emitting more metadata
   than before, or docs and READMEs that start claiming full PII removal.
5. **Fail-open error handling in the privacy path.** See "fail closed" below.
6. **Boundary violations.** This gem has zero runtime dependencies and no I/O. Flag any
   `system`, backticks, `%x`, `Open3`, `Kernel#exec`, `File`/`IO`/`Dir` access, `require 'net/http'`,
   socket use, `eval`, or a new runtime dependency in the gemspec. There is no legitimate reason for
   any of them here.
7. **Ordinary correctness bugs** in adapters, normalizers, models, and exporters: nil handling on
   malformed input, off-by-one turn indexes, `Regexp` captures assumed present, symbol versus string
   hash-key confusion between adapter output and consumer.

## Invariants that must never regress

- **INV-1 No egress.** No network, no filesystem, no subprocess, no runtime gem dependencies.
- **INV-2 Redaction is terminal.** Nothing leaves the library that has not been through the redactor
  in its final, post-truncation form.
- **INV-3 Privacy fails closed.** See below.
- **INV-4 Configuration freezes.** `configure` calls `freeze!`; every writer calls `check_frozen!`.
  A new config attribute without a validating writer and a `check_frozen!` guard is a defect.
  `reset_configuration!` is test-only.
- **INV-5 Value objects are immutable.** `Turn`, `Intent`, `ToolReference`, `Transcript`, and
  `TranscriptBatch` validate in the constructor and freeze their state. Adding a mutator, or handing
  out an unfrozen collection, breaks the guarantee the pipeline relies on when it rebuilds objects
  rather than editing them in place.
- **INV-6 Adapters validate.** Structurally invalid input raises `IngestionError`. Per-record
  skipping of an unparseable line is intentional and stays; whole-input garbage must still raise.
- **INV-7 Export schema is a contract.** Any change to the shape emitted by `Transcript#to_h`,
  `Turn#to_h`, or either exporter requires a `schema_version` bump and a matching edit to
  `000-docs/005-DR-DATA-data-contracts.md`. There is exactly one `schema_version`, emitted by
  `JsonExporter` in its base metadata and currently `'1.0'`; `MarkdownExporter` carries no version
  marker of its own, so a Markdown shape change bumps that same value. Downstream consumers parse
  this.
- **INV-8 Markdown export must not be forgeable in a way that misleads.** `MarkdownExporter` emits
  turn content as a bare body line, not inside a heading and not inside a code fence. The untrusted
  values it does interpolate into structural markup today are `source_id` into a `##` heading and
  `ToolReference#name` into inline backticks, both inside backticks the content can close. Turn
  content is unescaped, so it can still forge headings and fences of its own once it lands in the
  body. Treat any new interpolation of untrusted content into structural markup as a finding, and
  never build JSON by string concatenation instead of `JSON.generate`.

## What "fail closed" means here

In the privacy and export path, failure means **raise**, never "return the input unchanged".
Specifically: a bare `rescue` or `rescue => e` that swallows around `Redactor`, `ContentFilter`, or
an exporter is a defect; so is `rescue nil`, a `redact_*` method returning the original content on
error, and a guard clause that skips redaction when a value looks unusual (nil, non-String, empty,
frozen). What the code enforces today is narrower than the rule: `Redactor` raises `PrivacyError`
only when handed something that is not a `Turn` or a `Transcript`, and `redact_content` returns early
on blank content. There is no proof-of-processing check, so the rule is on the reviewer. Every new
failure path in this layer must raise rather than hand back the caller's content. Silence is the
failure mode that ships secrets.

Ingestion is the deliberate exception and is fail-soft by record: `ClaudeCodeAdapter#parse_line`
rescues `JSON::ParserError` and drops that line. That is intended. Fail-soft must never extend past
the adapter into normalization, privacy, or export.

## Generated, vendored, or out of scope

`Gemfile.lock` is gitignored and must not be committed. Nothing in this repo is generated or
vendored, so there is no "do not hand-edit" list to enforce; if a PR adds a generated artifact,
question why a zero-dependency library needs one. `planning/` is historical pre-implementation notes:
do not ask for it to be updated. `000-docs/008-AT-AUDT-*` is a dated audit record, so require a
dated successor rather than a silent rewrite.

## Do not waste comments on

RuboCop territory (line length, string literal style, method length, `frozen_string_literal`
comments) is enforced at zero offenses in CI and must not be restated. Also skip: RSpec naming and
`describe`/`context` wording, requests to add YARD docs, suggestions to add runtime dependencies or
extract a framework, tuning of `IntentDetector` confidence weights absent a concrete failure, and
rewrites of adapter structure on taste. The intent heuristics are explicitly best-effort.

## Anti-ratchet

On a re-review after new pushes the bar does not rise. Drop findings the update resolved and do not
invent objections on unchanged lines you previously accepted. Prefer a few high-conviction findings
over a sweep. If the change is correct, keeps the invariants, and cannot leak, reply `lgtm`. Both
lanes are advisory only and never block a merge.

## Sources

Every code-grounded claim above was read against the working tree at commit `fee7745`, the commit
this branch pointed at when the citations were written. Line numbers are from that commit. A
documented invariant is not an enforced one, so where the code enforces less than the rule states,
the entry says so.

Pipeline shape and the privacy path

- Sole redaction path, `redact_turn` and `redact_transcript`: `lib/wild_transcript_pipeline/privacy/redactor.rb:6`, `:22`, `:35`
- `WildTranscriptPipeline.process` public entry point: `lib/wild_transcript_pipeline.rb:47-51`
- Stage order in `run_pipeline` (normalize, redact turns, detect intents, extract tools, redact transcript): `lib/wild_transcript_pipeline.rb:64-71`
- Redaction is the last stage that produces exported content: `lib/wild_transcript_pipeline.rb:70`
- Exporter class names `Export::JsonExporter` and `Export::MarkdownExporter`: `lib/wild_transcript_pipeline/export/json_exporter.rb:7`, `lib/wild_transcript_pipeline/export/markdown_exporter.rb:5`
- Truncation to `max_turn_content_length` happens in `TurnNormalizer`, before the redactor: `lib/wild_transcript_pipeline/normalization/turn_normalizer.rb:22`, `:32-36` (invoked at `lib/wild_transcript_pipeline.rb:65`, one line before redaction at `:66`)
- `max_turn_content_length` default and writer: `lib/wild_transcript_pipeline/configuration.rb:15`, `:30-37`

Patterns (defect class 3)

- `BUILT_IN_PATTERNS`, seven constants: `lib/wild_transcript_pipeline/privacy/content_filter.rb:16-24`
- `apply_built_in_patterns` chain, the same seven plus two config-gated ones: `lib/wild_transcript_pipeline/privacy/redactor.rb:45-58`
- The two lists are separate and can drift: `content_filter.rb:16-24` against `redactor.rb:48-56`
- `ABSOLUTE_PATH_PATTERN`, the nested-quantifier regex: `lib/wild_transcript_pipeline/privacy/content_filter.rb:13`
- `FILE_CONTENT_PATTERN`, unbounded lazy scan: `lib/wild_transcript_pipeline/privacy/content_filter.rb:14`
- Both applied only when their config flag is on: `lib/wild_transcript_pipeline/privacy/redactor.rb:55-56`, `:70-76`

Metadata carve-out (defect class 4)

- `redact_turn` copies `turn.metadata` through untouched: `lib/wild_transcript_pipeline/privacy/redactor.rb:31`
- `Turn#to_h` emits `metadata`: `lib/wild_transcript_pipeline/models/turn.rb:21-28`
- It reaches the JSON payload through `Transcript#to_h`: `lib/wild_transcript_pipeline/models/transcript.rb:34`, `:37`, serialized at `lib/wild_transcript_pipeline/export/json_exporter.rb:29`
- `ClaudeCodeAdapter` writes raw `tool_input` and `tool_output` into metadata: `lib/wild_transcript_pipeline/ingestion/claude_code_adapter.rb:80-86`
- The recorded decision: `000-docs/003-TQ-STND-privacy-model.md:46-52` ("Scope Limitation")

Fail closed, and the ingestion exception (defect class 5)

- `PrivacyError` defined: `lib/wild_transcript_pipeline/errors.rb:7`
- The only `PrivacyError` raises today are wrong-type guards: `lib/wild_transcript_pipeline/privacy/redactor.rb:7`, `:23`
- Blank-content early return in `redact_content`: `lib/wild_transcript_pipeline/privacy/redactor.rb:36`
- `ClaudeCodeAdapter#parse_line` rescues `JSON::ParserError` and drops the line: `lib/wild_transcript_pipeline/ingestion/claude_code_adapter.rb:52-53`, dropped by `filter_map` at `:37`

INV-1 No egress

- Gemspec declares no runtime dependency: `wild-transcript-pipeline.gemspec:5-21`
- Only stdlib requires in the library: `lib/wild_transcript_pipeline.rb:3`, `lib/wild_transcript_pipeline/ingestion/base_adapter.rb:31`, and `require 'json'` at line 3 of `json_exporter.rb`, `claude_code_adapter.rb`, `generic_adapter.rb`, `mcp_log_adapter.rb`
- No `system`, backticks, `%x`, `Open3`, `exec`, `File`, `IO`, `Dir`, `net/http`, socket, or `eval` anywhere under `lib/`: verified by scanning the whole tree at `fee7745`, zero hits

INV-4 Configuration freezes

- `configure` calls `freeze!`: `lib/wild_transcript_pipeline.rb:36-39`
- `freeze!`: `lib/wild_transcript_pipeline/configuration.rb:88-91`
- `check_frozen!` in all seven writers: `lib/wild_transcript_pipeline/configuration.rb:24`, `:31`, `:40`, `:49`, `:58`, `:67`, `:79`; defined at `:95-97`
- `reset_configuration!` and its test-only status: `lib/wild_transcript_pipeline.rb:41-43`, documented at `000-docs/004-AT-ADEC-architecture-decisions.md:17`, `000-docs/006-DR-REFF-configuration-reference.md:12`, `CLAUDE.md:76`; used only by `spec/spec_helper.rb:24`

INV-5 Value objects

- `Turn` validates and freezes content and metadata: `lib/wild_transcript_pipeline/models/turn.rb:10-19`
- `Intent`: `lib/wild_transcript_pipeline/models/intent.rb:8-17`
- `ToolReference`: `lib/wild_transcript_pipeline/models/tool_reference.rb:11-22`
- `Transcript` validates then freezes its collections: `lib/wild_transcript_pipeline/models/transcript.rb:43-60`
- `TranscriptBatch`: `lib/wild_transcript_pipeline/models/transcript_batch.rb:8-15`
- Note: the objects freeze their state, they do not call `freeze` on themselves, and none defines a mutator

INV-6 Adapters validate

- `IngestionError` defined: `lib/wild_transcript_pipeline/errors.rb:5`
- Empty input: `lib/wild_transcript_pipeline/ingestion/base_adapter.rb:16-18`
- No parseable lines: `lib/wild_transcript_pipeline/ingestion/claude_code_adapter.rb:21`
- Whole-input JSON garbage and wrong top-level shape: `lib/wild_transcript_pipeline/ingestion/generic_adapter.rb:39-41`, `:51`; `lib/wild_transcript_pipeline/ingestion/mcp_log_adapter.rb:27`, `:30-31`
- Per-record skipping is intentional: `claude_code_adapter.rb:42`, `:45`, `:52`; `generic_adapter.rb:60`, `:64`; `mcp_log_adapter.rb:39`

INV-7 Export schema

- `Transcript#to_h`: `lib/wild_transcript_pipeline/models/transcript.rb:26-39`
- `Turn#to_h`: `lib/wild_transcript_pipeline/models/turn.rb:21-28`
- The single `schema_version`, value `'1.0'`: `lib/wild_transcript_pipeline/export/json_exporter.rb:33-39`
- The contract document it must match: `000-docs/005-DR-DATA-data-contracts.md:3`, `:12`, `:76`

INV-8 Markdown and JSON construction

- Turn content emitted as a bare body line, no heading, no fence: `lib/wild_transcript_pipeline/export/markdown_exporter.rb:95-104` (content at `:101`)
- `source_id` interpolated into a `##` heading inside backticks: `lib/wild_transcript_pipeline/export/markdown_exporter.rb:57`
- `ToolReference#name` interpolated into inline backticks: `lib/wild_transcript_pipeline/export/markdown_exporter.rb:84`
- JSON built with `JSON.generate`, never concatenation: `lib/wild_transcript_pipeline/export/json_exporter.rb:12`

Scope, authority, and the deterministic gate

- CI gate, rspec on Ruby 3.2 and 3.3 plus rubocop: `.github/workflows/ci.yml:14`, `:26`, `:29`
- `CLAUDE.md` "Safety Rules for Claude Code": `CLAUDE.md:69`
- `Gemfile.lock` gitignored, and untracked at this commit: `.gitignore:6`, confirmed with `git ls-files`
- `planning/` is pre-implementation scratch: `planning/notes.md:1-3`
- The dated audit record: `000-docs/008-AT-AUDT-appaudit-2026-05-28.md`
- `IntentDetector` confidence weights, the tuning this file tells reviewers to leave alone: `lib/wild_transcript_pipeline/normalization/intent_detector.rb:6-18`

Corrections made while citing

- INV-8 previously said turn content is interpolated into headings and fences. It is not. `MarkdownExporter` writes turn content as a plain body line (`markdown_exporter.rb:101`); the values that reach structural markup are `source_id` (`:57`) and `ToolReference#name` (`:84`). Corrected above.
- Defect class 3 previously called both `FILE_CONTENT_PATTERN` and `ABSOLUTE_PATH_PATTERN` nested-quantifier regexes. Only `ABSOLUTE_PATH_PATTERN` is nested (`content_filter.rb:13`); `FILE_CONTENT_PATTERN` is an unbounded lazy scan (`content_filter.rb:14`). Corrected above.
- The fail-closed section previously said the redactor raises `PrivacyError` when it cannot prove content was processed. No such check exists: the only raises are wrong-type guards (`redactor.rb:7`, `:23`) and blank content returns early (`:36`). Corrected above to state the rule as a reviewer obligation rather than an enforced behavior.
