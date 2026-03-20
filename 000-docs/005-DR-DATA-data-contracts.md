# 005 — Data Contracts: wild-transcript-pipeline

## JSON Export Schema (schema_version: "1.0")

Top-level structure from JsonExporter#export:

```json
{
  "metadata": {
    "generated_at": "<ISO8601>",
    "version": "<gem version>",
    "schema_version": "1.0"
  },
  "summary": {
    "transcript_count": <integer>,
    "total_turns": <integer>,
    "total_intents": <integer>,
    "total_tool_references": <integer>,
    "source_types": ["<symbol>"]
  },
  "transcripts": [<Transcript>]
}
```

## Transcript Object

```json
{
  "source_type": "<symbol: claude_code | mcp_log | generic>",
  "source_id": "<string>",
  "created_at": "<ISO8601>",
  "turn_count": <integer>,
  "intent_count": <integer>,
  "tool_reference_count": <integer>,
  "turns": [<Turn>],
  "intents": [<Intent>],
  "tool_references": [<ToolReference>],
  "metadata": {<string: any>}
}
```

## Turn Object

```json
{
  "role": "<symbol: user | assistant | system | tool>",
  "content": "<string>",
  "timestamp": "<ISO8601 or null>",
  "metadata": {<string: any>}
}
```

## Intent Object

```json
{
  "description": "<string — short description or excerpt>",
  "confidence": <float 0.0-1.0>,
  "source_turn_index": <integer — 0-based index into turns array>
}
```

## ToolReference Object

```json
{
  "name": "<string — tool name>",
  "action": "<symbol: called | mentioned | failed | not_found>",
  "outcome": "<symbol: success | error | not_available | null>",
  "turn_index": <integer — 0-based index into turns array>
}
```

## Stability Guarantee

Schema version 1.0 is stable. New optional keys may be added in minor versions. Existing keys will not be removed or renamed without a schema_version bump.

## Downstream Consumer Contract (wild-gap-miner)

Gap-miner expects:
- `transcripts[].turns` to contain redacted content (no raw PII)
- `transcripts[].intents` for gap detection (missing capabilities)
- `transcripts[].tool_references` where action=:not_found signals a gap
- `metadata.schema_version` to be checked before processing
