# 006 — Configuration Reference: wild-transcript-pipeline

## Usage

```ruby
WildTranscriptPipeline.configure do |c|
  c.redaction_marker = '[REDACTED]'
  c.max_turn_content_length = 10_000
end
```

After the block, the configuration is frozen. Call `WildTranscriptPipeline.reset_configuration!` to get a fresh unfrozen instance (test use only).

## Parameters

### redaction_marker

| Field | Value |
|-------|-------|
| Type | String |
| Default | `'[REDACTED]'` |
| Constraint | Non-empty string |
| Purpose | Replacement text for all redacted content |

### max_turn_content_length

| Field | Value |
|-------|-------|
| Type | Integer |
| Default | `10_000` |
| Constraint | Positive integer (>= 1) |
| Purpose | Maximum number of characters per turn before truncation |

### max_turns_per_transcript

| Field | Value |
|-------|-------|
| Type | Integer |
| Default | `1_000` |
| Constraint | Positive integer (>= 1) |
| Purpose | Maximum number of turns retained per transcript; excess turns are dropped (first N kept) |

### strip_file_contents

| Field | Value |
|-------|-------|
| Type | Boolean |
| Default | `true` |
| Constraint | `true` or `false` only |
| Purpose | When true, replaces markdown code fence blocks with `[marker:file_content]` |

### strip_absolute_paths

| Field | Value |
|-------|-------|
| Type | Boolean |
| Default | `true` |
| Constraint | `true` or `false` only |
| Purpose | When true, replaces absolute filesystem paths (matching `/...`) with redaction marker |

### custom_patterns

| Field | Value |
|-------|-------|
| Type | Array of Regexp |
| Default | `[]` |
| Constraint | All elements must be Regexp instances |
| Purpose | Additional patterns to apply during redaction, after built-in patterns |

### intent_confidence_threshold

| Field | Value |
|-------|-------|
| Type | Float |
| Default | `0.5` |
| Constraint | Between 0.0 and 1.0 inclusive |
| Purpose | Minimum confidence for an intent to be included in the transcript |

## Error Handling

All invalid values raise `WildTranscriptPipeline::ConfigurationError` with a descriptive message. Setting any value on a frozen configuration raises `FrozenError`.
