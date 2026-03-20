# 003 — Privacy Model: wild-transcript-pipeline

## Why This Matters

This gem handles conversation content from AI agent sessions. Those sessions may contain:
- User-supplied secrets (API keys, tokens, passwords)
- Personally identifiable information (email addresses, IP addresses)
- Sensitive infrastructure information (absolute file paths, server addresses)
- Embedded file contents with confidential code or configuration

The pipeline must strip all of this before exporting data to downstream consumers.

## Threat Model

| Threat | Mitigation |
|--------|-----------|
| API keys in turn content | Regex patterns for key=value and token formats |
| Email addresses in messages | Email regex applied before export |
| IP addresses in logs | IPv4 pattern applied universally |
| AWS credentials | AKIA/ASIA/AROA prefix patterns + secret key value patterns |
| GitHub PATs/app tokens | ghp_/ghs_ prefix patterns |
| Bearer tokens in auth headers | Bearer header pattern |
| Absolute paths revealing filesystem layout | Path stripping when strip_absolute_paths=true |
| File contents pasted into conversation | Code fence redaction when strip_file_contents=true |
| Custom organizational secrets | custom_patterns config accepts user-supplied Regexp array |

## Default Behavior

All redaction is enabled by default:
- strip_file_contents: true
- strip_absolute_paths: true
- redaction_marker: '[REDACTED]'
- All built-in patterns active

## Operator Responsibility

The built-in patterns are heuristic. They will miss novel secret formats. Operators who handle highly sensitive data should:
1. Add domain-specific patterns via custom_patterns
2. Review exported JSON before forwarding to third-party consumers
3. Never store raw transcripts — only normalized/redacted output

## Redaction Semantics

Redaction replaces matched content with the configured redaction_marker string. The marker is surrounded by no additional context — the replacement is exact. File content blocks are replaced with `[marker:file_content]`.

## Scope Limitation

This gem does NOT:
- Detect sensitive content in metadata fields (tool input/output values)
- Redact tool names or tool call argument structures
- Perform differential privacy or data synthesis
- Guarantee complete PII removal — it is best-effort based on known patterns
