# Changelog

All notable changes to wild-transcript-pipeline will be documented here.

## [0.1.0] - 2026-03-20

### Added
- Initial release
- Three ingestion adapters: ClaudeCodeAdapter, McpLogAdapter, GenericAdapter
- Normalization: TurnNormalizer, IntentDetector, ToolExtractor
- Privacy: ContentFilter, Redactor with built-in PII, secret, and path redaction
- Export: JsonExporter, MarkdownExporter
- Configuration system with freeze! support
- WildTranscriptPipeline.process convenience method
- 200+ RSpec tests, 0 failures, 0 RuboCop offenses
